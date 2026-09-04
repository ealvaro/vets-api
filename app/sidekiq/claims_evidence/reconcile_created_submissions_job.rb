# frozen_string_literal: true

require 'claims_evidence_api/folder_identifier'
require 'claims_evidence_api/service/search'
require 'lighthouse/benefits_documents/constants'

module ClaimsEvidence
  # Settles supplemental-claim submissions whose outcome was never established -- the file was
  # sent to Claims Evidence and a timeout or reset lost the answer. CE knows: contentName is
  # unique per eFolder, so a document filed under ours is ours.
  #
  # The appeals read path shows SUCCESS only, so a stuck row hides evidence that may have landed --
  # and at 60 days the row is purged, taking the contentName that could have found it.
  class ReconcileCreatedSubmissionsJob
    include Sidekiq::Job

    # No need to retry: the schedule runs this periodically and the work is idempotent.
    sidekiq_options retry: 0

    STATSD_KEY_PREFIX = 'worker.claims_evidence.reconcile_created_submissions'
    STATUS = BenefitsDocuments::Constants::UPLOAD_STATUS

    # What Claims Evidence records as uploadSource on our uploads (observed in staging)
    UPLOAD_SOURCE = 'VAGOV'
    STALE_AFTER = 5.minutes
    # Stop making attempts after this long. The row will still live to its delete_date, so a document
    # that turns up later can be matched by hand.
    EXHAUSTED_AFTER = 24.hours

    def perform
      filed = 0
      absent = 0
      mismatched = 0
      invalid = 0
      failed = 0

      stale_submissions.find_each do |submission|
        case reconcile(submission)
        when :filed then filed += 1
        when :absent then absent += 1
        when :upload_source_mismatch then mismatched += 1
        when :invalid_metadata then invalid += 1
        end
      rescue => e
        # One unresolvable row must not stop the rest; the next run will try again.
        failed += 1
        log_failure(submission, e)
      end

      report(filed, absent, mismatched, invalid, failed)
      report_exhausted
    end

    private

    # Scoped to Caseflow supplemental claims only
    def caseflow_created_submissions
      EvidenceSubmission
        .where(upload_status: STATUS[:CREATED])
        .where.not(caseflow_claim_id: nil)
    end

    def stale_submissions
      caseflow_created_submissions.where(created_at: EXHAUSTED_AFTER.ago..STALE_AFTER.ago)
    end

    def reconcile(submission)
      content_name = content_name_for(submission)
      return :invalid_metadata if content_name.blank?

      document = search_for_document(submission, content_name)
      return :absent if document.nil?

      upload_source = document.dig('currentVersion', 'systemData', 'uploadSource')
      return :upload_source_mismatch unless expected_upload_source?(upload_source)

      submission.update!(upload_status: STATUS[:SUCCESS], delete_date: 60.days.from_now)
      :filed
    end

    # We do not send uploadSource; Claims Evidence sets it.
    def expected_upload_source?(upload_source)
      upload_source == UPLOAD_SOURCE
    end

    def content_name_for(submission)
      JSON.parse(submission.template_metadata.to_s).dig('personalisation', 'content_name')
    rescue JSON::ParserError
      nil
    end

    def search_for_document(submission, content_name)
      icn = submission.user_account&.icn
      return nil if icn.blank?

      service = ClaimsEvidenceApi::Service::Search.new
      service.folder_identifier = ClaimsEvidenceApi::FolderIdentifier.generate('VETERAN', 'ICN', icn)

      body = service.find(filters: { contentName: content_name }).body
      Array(body['files']).first if body.is_a?(Hash)
    end

    def log_failure(submission, error)
      Rails.logger.warn(
        "#{self.class} could not reconcile an evidence submission",
        evidence_submission_id: submission&.id,
        error_class: error.class.name
      )
    end

    # Counts are sent even when zero, so a run that found nothing looks different from a run that
    # never happened.
    def report(filed, absent, mismatched, invalid, failed)
      StatsD.increment("#{STATSD_KEY_PREFIX}.count", filed, tags: ['outcome:filed'])
      StatsD.increment("#{STATSD_KEY_PREFIX}.count", absent, tags: ['outcome:absent'])
      StatsD.increment("#{STATSD_KEY_PREFIX}.count", mismatched,
                       tags: ['outcome:upload_source_mismatch'])
      StatsD.increment("#{STATSD_KEY_PREFIX}.count", invalid, tags: ['outcome:invalid_metadata'])
      StatsD.increment("#{STATSD_KEY_PREFIX}.error", failed)
      Rails.logger.info(
        "#{self.class} checked #{filed + absent + mismatched + invalid + failed} submissions " \
        "(#{filed} filed, #{absent} absent, #{mismatched} upload source mismatch, " \
        "#{invalid} invalid metadata, #{failed} errored)"
      )
      nil
    end

    def report_exhausted
      exhausted = caseflow_created_submissions.where(created_at: ...EXHAUSTED_AFTER.ago)

      StatsD.gauge("#{STATSD_KEY_PREFIX}.exhausted", exhausted.count)
    end
  end
end
