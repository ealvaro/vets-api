# frozen_string_literal: true

# SubmissionJob
#
# This Sidekiq job handles the submission of 10-10EZ health care applications to the HCA backend service.
#
# Why:
# - Automates the process of submitting user health care applications asynchronously.
# - Handles retries and error logging for robust, reliable processing.
#
# How:
# - Decrypts the submitted form data.
# - Submits the form to the HCA backend via the HCA::Service.
# - Updates the HealthCareApplication record with the result or error state.
# - Handles validation errors and logs them for analytics and auditing.
#
# See also: HCA::Service for submission logic, HealthCareApplication for persistence.

require 'hca/service'
require 'hca/soap_parser'
require 'sidekiq/monitored_worker'

module HCA
  class SubmissionJob
    include Sidekiq::Job
    include Sidekiq::MonitoredWorker

    VALIDATION_ERROR = HCA::SOAPParser::ValidationError

    # retry for  2d 1h 47m 12s
    # https://github.com/sidekiq/sidekiq/wiki/Error-Handling
    sidekiq_options retry: 16

    sidekiq_retries_exhausted do |msg, _e|
      health_care_application = HealthCareApplication.find(msg['args'][2])
      form = decrypt_form(msg['args'][1])

      health_care_application.update!(
        state: 'failed',
        form: form.to_json,
        google_analytics_client_id: msg['args'][3]
      )
    end

    def retry_limits_for_notification
      [10]
    end

    def notify(params)
      # Add 1 to retry_count to match retry_monitoring logic
      retry_count = params['retry_count'].to_i + 1
      health_care_application_id = params['args'][2]

      if retry_count == 10
        StatsD.increment("#{HCA::Service::STATSD_KEY_PREFIX}.async.failed_ten_retries",
                         tags: ["health_care_application_id:#{health_care_application_id}"])
      end
    end

    def self.decrypt_form(encrypted_form)
      JSON.parse(HealthCareApplication::LOCKBOX.decrypt(encrypted_form))
    end

    def submit(user_identifier, form, google_analytics_client_id)
      begin
        result = HCA::Service.new(user_identifier).submit_form(form)
      rescue VALIDATION_ERROR
        handle_enrollment_system_validation_error(form, google_analytics_client_id)
        return false
      end

      result
    end

    def perform(user_identifier, encrypted_form, health_care_application_id, google_analytics_client_id)
      @health_care_application = HealthCareApplication.find(health_care_application_id)
      form = nil
      current_retry_attempt = retry_attempt
      form = self.class.decrypt_form(encrypted_form)
      attachment_guids = extract_attachment_guids(form, fallback: 'none')
      log_submission_start(health_care_application_id, attachment_guids, current_retry_attempt)

      result = submit(user_identifier, form, google_analytics_client_id)
      return unless result

      Rails.logger.info "[10-10EZ] - SubmissionID=#{result[:formSubmissionId]}"
      @health_care_application.form = form.to_json
      @health_care_application.set_result_on_success!(result)
    rescue => e
      @health_care_application.update!(state: 'error')
      failed_guids = extract_attachment_guids(form, fallback: 'unknown')
      log_submission_failure(health_care_application_id, failed_guids, current_retry_attempt, e)

      raise
    end

    private

    def handle_enrollment_system_validation_error(form, google_analytics_client_id)
      StatsD.increment("#{HCA::Service::STATSD_KEY_PREFIX}.enrollment_system_validation_error")
      PersonalInformationLog.create!(
        data: { form: },
        error_class: VALIDATION_ERROR.to_s
      )

      @health_care_application.update!(
        state: 'failed',
        form: form.to_json,
        google_analytics_client_id:
      )
    end

    def retry_attempt
      sidekiq_context = Thread.current[:sidekiq_context]
      return nil unless sidekiq_context.is_a?(Hash)

      retry_count = sidekiq_context[:retry_count] || sidekiq_context['retry_count']
      retry_count&.to_i
    end

    def extract_attachment_guids(form, fallback:)
      form&.dig('attachments')
          &.map { |attachment| attachment['confirmationCode'] }
          &.compact
          &.join(',')
          .presence || fallback
    end

    def log_submission_start(health_care_application_id, attachment_guids, current_retry_attempt)
      Rails.logger.info(
        '[HCA_SUBMISSION] 10-10EZ async submission initiated | ' \
        "health_care_application_id=#{health_care_application_id} | " \
        "attachment_guids=#{attachment_guids} | " \
        "retry_attempt=#{current_retry_attempt}"
      )
    end

    def log_submission_failure(health_care_application_id, attachment_guids, current_retry_attempt, error)
      Rails.logger.error(
        '[HCA_SUBMISSION_FAILED] 10-10EZ async submission failed | ' \
        "health_care_application_id=#{health_care_application_id} | " \
        "attachment_guids=#{attachment_guids} | " \
        "retry_attempt=#{current_retry_attempt}",
        exception: error
      )
    end
  end
end
