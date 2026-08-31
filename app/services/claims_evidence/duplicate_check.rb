# frozen_string_literal: true

require 'lighthouse/benefits_documents/constants'

module ClaimsEvidence
  # Rejects the same file being uploaded twice, in two layers:
  #
  #   presumed_duplicate? - matches prior SUCCESS rows, so it only catches repeats once an
  #                         earlier upload has landed.
  #   acquire_lock        - a short Redis lock covering the window before that row exists.
  #                         The frontend uploads files in parallel, so two copies of one
  #                         file can clear the first layer at the same moment.
  #
  # A file is identified by (user, claim, document type, name, size). Content is not
  # hashed, so a renamed file slips through — a deliberate tradeoff. Both layers fail
  # open: a Redis outage must not stop a Veteran filing evidence.
  class DuplicateCheck
    LOCK_NAMESPACE = 'claims-evidence-upload'
    # Only has to cover one upload request — tempfile copy, PDF unlock, virus scan, CE call,
    # DB insert.
    LOCK_TTL = 2.minutes
    LOCK_UNAVAILABLE_MESSAGE = 'ClaimsEvidence::DuplicateCheck lock unavailable, failing open'
    LOCK_RELEASE_FAILED_MESSAGE = 'ClaimsEvidence::DuplicateCheck lock release failed, it will expire on its own'

    # @param upload [ClaimsEvidence::UploadRequest]
    def initialize(current_user:, upload:, cache: Rails.cache)
      @current_user = current_user
      @upload = upload
      @cache = cache
    end

    # template_metadata is encrypted and cannot be matched in SQL, so narrow on the
    # indexed columns and compare the decrypted payload in Ruby.
    def presumed_duplicate?
      candidate_submissions.any? do |submission|
        personalisation = parse_personalisation(submission)
        personalisation['file_name'] == @upload.file_name &&
          personalisation['document_type_id'] == @upload.doc_type_id
      end
    end

    # @return [Boolean] true if this request may proceed — it took the lock, or the cache was
    # unreachable and we failed open. False means another request holds the lock.
    def acquire_lock
      claimed = @cache.write(lock_key, true, namespace: LOCK_NAMESPACE,
                                             expires_in: LOCK_TTL,
                                             unless_exist: true)
      # RedisCacheStore turns connection errors into nil; false means the key really exists.
      return claimed unless claimed.nil?

      lock_unavailable
    rescue => e
      # RedisCacheStore's failsafe covers Redis and connection pool errors, but the cache is
      # injectable and any other store makes no such promise. Fail open rather than let our
      # own dedupe 500 an upload.
      lock_unavailable(e)
    end

    # Best effort. By the time anything releases the lock the file is in the eFolder, so a
    # cache error here must not fail the request; the lock just expires on its own instead.
    #
    # @param retry_blocked [Boolean] whether stranding the lock blocks a legitimate retry.
    #   True when no EvidenceSubmission row was written, so presumed_duplicate? has nothing to
    #   fall back on and the Veteran gets a 422 until the TTL expires. False when the row does
    #   exist, since the first layer then rejects repeats on its own. Required rather than
    #   defaulted: it drives the monitor, so a new call site has to decide which case it is.
    def release_lock(retry_blocked:)
      @cache.delete(lock_key, namespace: LOCK_NAMESPACE)
    rescue => e
      Rails.logger.warn("#{LOCK_RELEASE_FAILED_MESSAGE}: #{e.class}")
      ClaimsEvidence::Metrics.increment('duplicate_check.release_failure',
                                        error_class: e.class.name, retry_blocked:)
      nil
    end

    private

    # @return [true] always: no lock means no dedupe, not a blocked upload
    def lock_unavailable(error = nil)
      Rails.logger.warn([LOCK_UNAVAILABLE_MESSAGE, error&.class].compact.join(': '))
      ClaimsEvidence::Metrics.increment('duplicate_check.skipped', error_class: error&.class&.name)
      true
    end

    def candidate_submissions
      EvidenceSubmission.where(
        caseflow_claim_id: @upload.sc_id,
        user_account: @current_user.user_account,
        upload_status: BenefitsDocuments::Constants::UPLOAD_STATUS[:SUCCESS],
        file_size: @upload.file_size
      )
    end

    # Guards both levels: a non-object payload, and a personalisation key holding something
    # other than an object. The inner check matters because a String there would raise
    # NoMethodError, which the JSON::ParserError rescue does not catch.
    def parse_personalisation(submission)
      parsed = JSON.parse(submission.template_metadata.to_s)
      personalisation = parsed.is_a?(Hash) ? parsed['personalisation'] : nil
      personalisation.is_a?(Hash) ? personalisation : {}
    rescue JSON::ParserError
      {}
    end

    # Keyed on doc_type_id rather than document_type: the id is stable, the label is display
    # text that can be reworded without changing which document type it refers to.
    def lock_key
      @lock_key ||= Digest::SHA256.hexdigest(
        [@current_user.user_account_uuid, @upload.sc_id, @upload.doc_type_id,
         @upload.file_name, @upload.file_size].join('|')
      )
    end
  end
end
