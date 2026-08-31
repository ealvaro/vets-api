# frozen_string_literal: true

require 'claims_evidence_api/service/files'
require 'claims_evidence_api/folder_identifier'
require 'lighthouse/benefits_documents/constants'
require 'logging/helper/data_scrubber'

module ClaimsEvidence
  class UploadEvidence
    RELATIVE_SCAN_DIR = 'clamav_tmp'

    # Internal signal, translated to a 422 by the controller.
    class DuplicateUpload < StandardError; end

    # What the controller renders once the file is filed.
    Result = Data.define(:payload, :status)

    # @param current_user [User]
    # @param upload [ClaimsEvidence::UploadRequest] the validated file and its metadata
    # @param password [String, nil] supplied by the Veteran for an encrypted PDF
    def initialize(current_user:, upload:, password: nil)
      @current_user = current_user
      @upload = upload
      @password = password
    end

    # @return [Result]
    # @raise [DuplicateUpload] the same file is already filed, or is mid-flight in another request
    # @raise [ClaimsEvidence::PdfUnlocker::Rejected] something about the PDF the Veteran can fix
    # @raise [ClaimsEvidenceApi::Service::Files::VirusFound]
    def call
      copy_and_upload(guard_duplicate_upload)
    rescue DuplicateUpload, ClaimsEvidence::PdfUnlocker::Rejected
      # Already counted where it was raised, or counted by the controller as a validation
      # failure.
      raise
    rescue ClaimsEvidenceApi::Service::Files::VirusFound
      increment_upload_failure(reason: 'virus')
      raise
    rescue => e
      increment_upload_failure(error_class: e.class.name)
      raise
    end

    private

    # @return [ClaimsEvidence::DuplicateCheck] holding the lock, for the caller to release
    # detected_by names what the duplicate matched: an upload that already finished, or one
    # still running in a parallel request.
    def guard_duplicate_upload
      duplicate_check = ClaimsEvidence::DuplicateCheck.new(current_user: @current_user, upload: @upload)

      raise_duplicate(detected_by: 'completed') if duplicate_check.presumed_duplicate?
      raise_duplicate(detected_by: 'in_flight') unless duplicate_check.acquire_lock

      duplicate_check
    end

    def raise_duplicate(detected_by:)
      increment_upload_failure(reason: 'duplicate', detected_by:)
      raise DuplicateUpload
    end

    def copy_and_upload(duplicate_check)
      evidence_accepted = false
      prefix = File.basename(@upload.file_name, '.*').to_s[0, 50].presence || 'claims-evidence'
      FileUtils.mkdir_p(Rails.root.join(RELATIVE_SCAN_DIR))
      Tempfile.create([prefix, File.extname(@upload.file_name)], RELATIVE_SCAN_DIR) do |tmp|
        tmp.binmode
        @upload.file.tempfile.rewind
        IO.copy_stream(@upload.file.tempfile, tmp)
        tmp.flush
        # Decrypt before the virus scan and upload, so both see readable bytes.
        ClaimsEvidence::PdfUnlocker.new(tmp, @upload.file_name, password: @password).unlock!
        ce_response = ce_service.upload(tmp.path, provider_data: build_provider_data)
        # Set the moment Claims Evidence takes the file: from here on nothing may release
        # the lock, because the document is in the eFolder whatever happens next.
        evidence_accepted = true

        # Order matters: save the record first, since the file is already in the eFolder. Build the
        # payload before counting success, so a response body we can't read is only counted as a failure.
        duplicate_check.release_lock(retry_blocked: false) if persist_evidence_submission(ce_response)
        payload = build_upload_response_payload(ce_response.body)
        log_upload_success
        Result.new(payload:, status: ce_response.status)
      end
    rescue
      # The file never reached Claims Evidence, so free the lock for an immediate retry. If this
      # release fails the lock is stranded and that retry 422s until the TTL expires.
      duplicate_check.release_lock(retry_blocked: true) unless evidence_accepted
      raise
    end

    def build_upload_response_payload(response_body)
      unless response_body.is_a?(Hash)
        raise TypeError, "Unexpected Claims Evidence response body class: #{response_body.class.name}"
      end

      response_body.slice('uuid', 'currentVersionUuid')
    end

    # Never fail the upload response because of a persistence miss:
    # the file is already in the eFolder.
    def persist_evidence_submission(ce_response)
      EvidenceSubmission.create!(
        caseflow_claim_id: @upload.sc_id,
        user_account: @current_user.user_account,
        upload_status: BenefitsDocuments::Constants::UPLOAD_STATUS[:SUCCESS],
        file_size: @upload.file_size,
        delete_date: 60.days.from_now,
        template_metadata: { personalisation: { file_name: @upload.file_name,
                                                document_type_id: @upload.doc_type_id,
                                                document_type: @upload.document_type } }.to_json
      )
    rescue => e
      log_persist_failure(e, ce_response)
      nil # StatsD.increment returns truthy; nil stops the caller releasing the lock
    end

    def log_persist_failure(error, ce_response)
      Rails.logger.error(
        'ClaimsEvidenceController#persist_evidence_submission failed',
        document_type_id: @upload.doc_type_id,
        supplemental_claim_id: @upload.sc_id,
        error_class: error.class.name,
        error: Logging::Helper::DataScrubber.scrub(error.message)
      )
      ClaimsEvidence::Metrics.increment('persist.failure', error_class: error.class.name)
      capture_submission_for_backfill(ce_response)
    end

    # The document is already in the eFolder but has no EvidenceSubmission row, and the
    # request still returns 200. Capture everything needed to recreate the row by hand.
    def capture_submission_for_backfill(ce_response)
      ce_body = readable_body(ce_response)
      PersonalInformationLog.create(
        error_class: 'ClaimsEvidenceController#persist_evidence_submission',
        data: {
          caseflow_claim_id: @upload.sc_id,
          user_account_id: @current_user.user_account&.id,
          icn: @current_user.icn,
          document_type_id: @upload.doc_type_id,
          document_type: @upload.document_type,
          file_name: @upload.file_name,
          file_size: @upload.file_size,
          claims_evidence_uuid: ce_body&.dig('uuid'),
          claims_evidence_current_version_uuid: ce_body&.dig('currentVersionUuid'),
          upload_status: BenefitsDocuments::Constants::UPLOAD_STATUS[:SUCCESS],
          delete_date: 60.days.from_now
        }
      )
    rescue => e
      log_backfill_capture_failure(e, ce_body)
    end

    def readable_body(ce_response)
      body = ce_response&.body
      body if body.is_a?(Hash)
    end

    # Last line of defense: no EvidenceSubmission row and no PII log, while the document sits
    # in the eFolder. The CE uuid is the only remaining recovery anchor --
    # ClaimsEvidenceApi::Service::Files#retrieve can fetch the document metadata from it
    def log_backfill_capture_failure(error, ce_body)
      Rails.logger.error(
        'ClaimsEvidenceController#capture_submission_for_backfill failed',
        supplemental_claim_id: @upload.sc_id,
        user_account_uuid: @current_user&.user_account_uuid,
        document_type_id: @upload.doc_type_id,
        claims_evidence_uuid: ce_body&.dig('uuid'),
        error_class: error.class.name
      )
      ClaimsEvidence::Metrics.increment('persist.unrecoverable', error_class: error.class.name)
    end

    # Best effort: the file is uploaded and the record is saved by now, so a broken metric or log
    # must not fail the request. Without this, an error here skips the result and the controller
    # turns a successful upload into a 500 with a false failure metric.
    def log_upload_success
      ClaimsEvidence::Metrics.increment('upload.success', document_type_id: @upload.doc_type_id)
      Rails.logger.info('ClaimsEvidenceController#create upload success',
                        document_type: @upload.document_type)
    rescue
      nil
    end

    def increment_upload_failure(**extra_tags)
      ClaimsEvidence::Metrics.increment('upload.failure', **extra_tags,
                                        document_type_id: @upload.doc_type_id)
    end

    def build_provider_data
      {
        contentSource: ClaimsEvidenceApi::CONTENT_SOURCE,
        dateVaReceivedDocument: Time.zone.now.in_time_zone(ClaimsEvidenceApi::TIMEZONE).strftime('%Y-%m-%d'),
        documentTypeId: @upload.doc_type_id
      }
    end

    def ce_service
      service = ClaimsEvidenceApi::Service::Files.new
      service.folder_identifier = ClaimsEvidenceApi::FolderIdentifier.generate('VETERAN', 'ICN', @current_user.icn)
      service
    end
  end
end
