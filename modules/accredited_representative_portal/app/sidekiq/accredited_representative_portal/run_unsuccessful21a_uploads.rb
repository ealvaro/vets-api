# frozen_string_literal: true

require 'sidekiq'

module AccreditedRepresentativePortal
  class RunUnsuccessful21aUploads
    include Sidekiq::Job

    sidekiq_options retry: 7, unique_for: 2.hours

    DATADOG_REDRIVE_ENQUEUED_METRIC = 'api.form21a.document_upload.redrive_enqueued'
    DATADOG_ABANDONED_METRIC = 'api.form21a.document_upload.abandoned'
    DATADOG_STUCK_METRIC = 'api.form21a.document_upload.stuck'

    ABANDONABLE_STATUSES = %w[
      failed_transient
      pending
      uploading
    ].freeze

    STUCK_STATUSES = %w[
      pending
      uploading
    ].freeze

    KNOWN_CONTENT_TYPES = %w[
      application/pdf
      application/vnd.openxmlformats-officedocument.wordprocessingml.document
    ].freeze

    # UploadForm21aDocumentToGCLAWSJob records:
    # - one failed attempt per Sidekiq execution
    # - one terminal attempt in sidekiq_retries_exhausted
    #
    # Sidekiq retry: 2 means 3 executions, plus 1 exhausted terminal attempt.
    UPLOAD_JOB_RETRY_COUNT = UploadForm21aDocumentToGCLAWSJob.sidekiq_options['retry'].to_i
    ATTEMPTS_RECORDED_PER_EXHAUSTED_UPLOAD_JOB = UPLOAD_JOB_RETRY_COUNT + 2
    INITIAL_EXHAUSTED_ATTEMPT_COUNT = ATTEMPTS_RECORDED_PER_EXHAUSTED_UPLOAD_JOB

    BACKOFF_SCHEDULE = [
      4.hours,
      8.hours,
      12.hours,
      24.hours
    ].freeze

    STUCK_ALERT_THROTTLE = 24.hours

    def perform
      abandon_genuinely_stuck_documents
      surface_stuck_stragglers
      redrive_due_transient_failures
    end

    private

    def abandon_genuinely_stuck_documents
      abandonable_submissions.find_each do |submission|
        next unless submission.genuinely_stuck?

        abandon_submission!(
          submission,
          reason: abandoned_reason_for(submission)
        )
      end
    end

    def abandonable_submissions
      Form21aDocumentSubmission
        .where(latest_status: 'failed_transient')
        .or(
          Form21aDocumentSubmission
            .where(latest_status: %w[pending uploading])
            .where('created_at <= ?', Form21aDocumentSubmission::ABANDON_THRESHOLD.ago)
        )
    end

    def surface_stuck_stragglers
      Form21aDocumentSubmission.stuck.find_each do |submission|
        surface_stuck_straggler(submission)
      end
    end

    def surface_stuck_straggler(submission)
      should_alert = false

      submission.with_lock do
        submission.reload

        if stuck_alert_due?(submission)
          submission.update!(last_stuck_alerted_at: Time.current)
          should_alert = true
        end
      end

      submission.reload
      emit_stuck_alert(submission) if should_alert && STUCK_STATUSES.include?(submission.latest_status)
    end

    def stuck_alert_due?(submission)
      STUCK_STATUSES.include?(submission.latest_status) &&
        submission.created_at.present? &&
        submission.created_at <= Form21aDocumentSubmission::STUCK_THRESHOLD.ago &&
        (
          submission.last_stuck_alerted_at.blank? ||
          submission.last_stuck_alerted_at <= STUCK_ALERT_THROTTLE.ago
        )
    end

    def redrive_due_transient_failures
      submissions_by_application = redrivable_submissions_by_application
      successful_application_ids = successful_application_ids_for(submissions_by_application.keys)

      submissions_by_application.each do |application_id, submissions|
        submissions_to_redrive_for(application_id, submissions, successful_application_ids).each do |submission|
          redrive_submission(submission)
        end
      end
    end

    def redrivable_submissions_by_application
      Form21aDocumentSubmission
        .redrivable
        .order(:application_id, :created_at)
        .to_a
        .group_by(&:application_id)
    end

    def submissions_to_redrive_for(application_id, submissions, successful_application_ids)
      return submissions if successful_application_ids.include?(application_id)

      [submissions.first]
    end

    def successful_application_ids_for(application_ids)
      return Set.new if application_ids.blank?

      Form21aDocumentSubmission
        .latest_status_succeeded
        .where(application_id: application_ids)
        .distinct
        .pluck(:application_id)
        .to_set
    end

    def redrive_submission(submission)
      should_abandon = false
      abandon_reason = nil

      submission.with_lock do
        submission.reload

        if submission.retry_due?
          if submission.genuinely_stuck?
            should_abandon = true
            abandon_reason = abandoned_reason_for(submission)
          else
            schedule_next_retry!(submission)
            enqueue_upload_job(submission)
          end
        end
      end

      abandon_submission!(submission, reason: abandon_reason) if should_abandon
    end

    def schedule_next_retry!(submission)
      attempted_at = Time.current

      submission.update!(
        last_attempted_at: attempted_at,
        next_retry_at: attempted_at + backoff_interval_for(submission)
      )
    end

    def backoff_interval_for(submission)
      BACKOFF_SCHEDULE.fetch(backoff_schedule_index_for(submission))
    end

    def backoff_schedule_index_for(submission)
      redrive_round = [
        (submission.attempt_count - INITIAL_EXHAUSTED_ATTEMPT_COUNT) / ATTEMPTS_RECORDED_PER_EXHAUSTED_UPLOAD_JOB,
        0
      ].max

      [redrive_round, BACKOFF_SCHEDULE.length - 1].min
    end

    def enqueue_upload_job(submission)
      UploadForm21aDocumentToGCLAWSJob.perform_async(
        submission.form21a_attachment_guid,
        submission.application_id,
        submission.document_type,
        submission.original_file_name,
        submission.content_type
      )

      emit_redrive_enqueued(submission)
    end

    def abandon_submission!(submission, reason:)
      abandoned_attempt = nil

      submission.with_lock do
        submission.reload

        if ABANDONABLE_STATUSES.include?(submission.latest_status) && submission.genuinely_stuck?
          attempted_at = Time.current

          abandoned_attempt = submission.submission_attempts.create!(
            status: 'abandoned',
            attempted_at:,
            metadata: abandoned_metadata_for(submission, reason)
          )

          submission.update!(
            last_attempted_at: attempted_at,
            next_retry_at: nil
          )
        end
      end

      emit_abandoned_alert(submission.reload, reason:, abandoned_attempt:) if abandoned_attempt
    end

    def abandoned_reason_for(submission)
      if submission.attempt_count >= Form21aDocumentSubmission::REDRIVE_MAX_ATTEMPTS
        return 'max_redrive_attempts_reached'
      end

      'abandon_threshold_exceeded'
    end

    def abandoned_metadata_for(submission, reason)
      {
        'job_class' => self.class.name,
        'reason' => reason,
        'form21a_attachment_guid' => submission.form21a_attachment_guid,
        'application_id' => submission.application_id,
        'document_type' => submission.document_type,
        'attempt_count' => submission.attempt_count,
        'created_at' => submission.created_at&.iso8601,
        'abandon_threshold' => Form21aDocumentSubmission::ABANDON_THRESHOLD.inspect,
        'redrive_max_attempts' => Form21aDocumentSubmission::REDRIVE_MAX_ATTEMPTS
      }
    end

    def emit_redrive_enqueued(submission)
      StatsD.increment(
        DATADOG_REDRIVE_ENQUEUED_METRIC,
        tags: datadog_tags_for(submission)
      )

      Rails.logger.info(
        'RunUnsuccessful21aUploads: Re-enqueued Form 21a document upload. ' \
        "guid=#{submission.form21a_attachment_guid} " \
        "application_id=#{submission.application_id} " \
        "document_type=#{submission.document_type} " \
        "next_retry_at=#{submission.next_retry_at}"
      )
    end

    def emit_abandoned_alert(submission, reason:, abandoned_attempt:)
      attempt_count = abandoned_attempt_count_for(submission, abandoned_attempt)

      StatsD.increment(
        DATADOG_ABANDONED_METRIC,
        tags: datadog_tags_for(submission).append("reason:#{reason}")
      )

      Rails.logger.error(
        'RunUnsuccessful21aUploads: Form 21a document upload abandoned. ' \
        "guid=#{submission.form21a_attachment_guid} " \
        "application_id=#{submission.application_id} " \
        "document_type=#{submission.document_type} " \
        "latest_status=#{submission.latest_status} " \
        "attempt_count=#{attempt_count} " \
        "reason=#{reason}"
      )

      notify_slack(
        class: self.class.name,
        alert: '[ALERT] Form 21a document upload abandoned',
        details: abandoned_slack_details(submission, reason:, attempt_count:)
      )
    end

    def abandoned_attempt_count_for(submission, abandoned_attempt)
      abandoned_attempt.metadata&.fetch('attempt_count', nil) || submission.attempt_count
    end

    def emit_stuck_alert(submission)
      StatsD.increment(
        DATADOG_STUCK_METRIC,
        tags: datadog_tags_for(submission).append("latest_status:#{submission.latest_status}")
      )

      Rails.logger.error(
        'RunUnsuccessful21aUploads: Form 21a document upload is stuck in non-terminal status. ' \
        "guid=#{submission.form21a_attachment_guid} " \
        "application_id=#{submission.application_id} " \
        "document_type=#{submission.document_type} " \
        "latest_status=#{submission.latest_status} " \
        "created_at=#{submission.created_at} " \
        "last_stuck_alerted_at=#{submission.last_stuck_alerted_at}"
      )

      notify_slack(
        class: self.class.name,
        alert: '[ALERT] Form 21a document upload stuck in non-terminal status',
        details: stuck_slack_details(submission)
      )
    end

    def notify_slack(payload)
      VBADocuments::Slack::Messenger.new(payload).notify!
    rescue => e
      Rails.logger.error(
        'RunUnsuccessful21aUploads: Failed to send Slack alert.',
        exception: e
      )
    end

    def abandoned_slack_details(submission, reason:, attempt_count:)
      [
        "guid: #{submission.form21a_attachment_guid}",
        "application_id: #{submission.application_id}",
        "document_type: #{submission.document_type}",
        "content_type: #{submission.content_type}",
        "latest_status: #{submission.latest_status}",
        "attempt_count: #{attempt_count}",
        "created_at: #{submission.created_at}",
        "last_attempted_at: #{submission.last_attempted_at}",
        "reason: #{reason}"
      ].join("\n")
    end

    def stuck_slack_details(submission)
      [
        "guid: #{submission.form21a_attachment_guid}",
        "application_id: #{submission.application_id}",
        "document_type: #{submission.document_type}",
        "content_type: #{submission.content_type}",
        "latest_status: #{submission.latest_status}",
        "attempt_count: #{submission.attempt_count}",
        "created_at: #{submission.created_at}",
        "last_attempted_at: #{submission.last_attempted_at}",
        "last_stuck_alerted_at: #{submission.last_stuck_alerted_at}"
      ].join("\n")
    end

    def datadog_tags_for(submission)
      [
        "document_type:#{safe_document_type_tag(submission)}",
        "content_type:#{safe_content_type_tag(submission)}"
      ]
    end

    def safe_document_type_tag(submission)
      document_type = submission.document_type.to_s

      known_document_type_tags.include?(document_type) ? document_type : 'other'
    end

    def safe_content_type_tag(submission)
      content_type = submission.content_type.to_s

      KNOWN_CONTENT_TYPES.include?(content_type) ? content_type : 'other'
    end

    def known_document_type_tags
      @known_document_type_tags ||= Form21aDocumentUploadConstants::DOCUMENT_TYPES.values.to_set(&:to_s)
    end
  end
end
