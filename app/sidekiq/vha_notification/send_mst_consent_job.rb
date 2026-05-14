# frozen_string_literal: true

require 'vha_notification/service'

module VHANotification
  class SendMstConsentJob
    include Sidekiq::Job

    STATSD_KEY_PREFIX = 'worker.vha_notification.send_mst_consent'
    RETRY = 16

    sidekiq_options retry: RETRY

    sidekiq_retries_exhausted do |msg, ex|
      form526_submission_id, submission_path = msg['args']
      error_class = msg['error_class'] || ex&.class&.to_s
      error_message = msg['error_message'] || ex&.message

      StatsD.increment("#{STATSD_KEY_PREFIX}.exhausted")
      Rails.logger.error(
        'VHA Notification MST consent job retries exhausted',
        {
          form526_submission_id:,
          submission_path: submission_path || 'primary',
          error_class:,
          error_message:
        }
      )
    end

    # @param form526_submission_id [Integer]
    # @param submission_path [String] primary|backup
    def perform(form526_submission_id, submission_path = 'primary')
      processed = send_consent_for_submission(form526_submission_id, submission_path)
      log_success(form526_submission_id, submission_path) if processed
    rescue => e
      log_failure(form526_submission_id, submission_path, e)
      raise
    ensure
      StatsD.increment("#{STATSD_KEY_PREFIX}.total")
    end

    private

    def send_consent_for_submission(form526_submission_id, submission_path)
      submission = Form526Submission.find(form526_submission_id)

      mst_consent = mst_consent_value(submission)
      if mst_consent.nil?
        log_skip(skip_reason(submission), submission_path, form526_submission_id)
        return false
      end

      participant_id = participant_id_for(submission, submission_path, form526_submission_id)
      return false if participant_id.nil?

      VHANotification::Service.new.send_mst_consent(participant_id, mst_consent)
      true
    end

    def participant_id_for(submission, submission_path, form526_submission_id)
      participant_id = submission.auth_headers['va_eauth_pid'].to_s.strip
      return participant_id if participant_id.present?

      log_skip('missing_participant_id', submission_path, form526_submission_id)
      nil
    end

    def log_success(form526_submission_id, submission_path)
      StatsD.increment("#{STATSD_KEY_PREFIX}.success")
      Rails.logger.info(
        'VHA Notification MST consent job succeeded',
        { form526_submission_id:, submission_path: }
      )
    end

    def log_failure(form526_submission_id, submission_path, error)
      StatsD.increment("#{STATSD_KEY_PREFIX}.failure")
      Rails.logger.error(
        'VHA Notification MST consent job failed',
        {
          form526_submission_id:,
          submission_path:,
          error_class: error.class.to_s,
          error_message: error.message
        }
      )
    end

    def mst_consent_value(submission)
      case option_indicator(submission)
      when 'yes'
        true
      when 'no', 'revoke'
        false
      end
    end

    def skip_reason(submission)
      indicator = option_indicator(submission)

      if indicator == 'notenrolled'
        'not_enrolled'
      else
        'no_consent'
      end
    end

    def option_indicator(submission)
      submission.form.dig('form0781', 'form0781v2', 'optionIndicator').to_s.delete('_').downcase
    end

    def log_skip(reason, submission_path, form526_submission_id)
      StatsD.increment("#{STATSD_KEY_PREFIX}.skipped", tags: ["reason:#{reason}", "path:#{submission_path}"])
      Rails.logger.info(
        'VHA Notification MST consent job skipped',
        { form526_submission_id:, submission_path:, reason: }
      )
    end
  end
end
