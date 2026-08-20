# frozen_string_literal: true

# EzrSubmissionJob
#
# This Sidekiq job handles the submission of 10-10EZR (health care renewal) forms to the backend service.
#
# Why:
# - Automates and manages the asynchronous submission of renewal forms.
# - Handles retries, error logging, and user notification on failure.
#
# How:
# - Decrypts the submitted form data.
# - Submits the form via Form1010Ezr::Service.
# - Handles validation and parsing errors, logs failures, and sends notification emails if enabled.
# - Increments StatsD metrics for monitoring and analytics.
#
# See also: Form1010Ezr::Service for submission logic, Flipper flag for notification emails.

require 'hca/soap_parser'
require 'form1010_ezr/service'

module HCA
  class EzrSubmissionJob
    include Sidekiq::Job

    FORM_ID = '10-10EZR'
    VALIDATION_ERROR = HCA::SOAPParser::ValidationError
    STATSD_KEY_PREFIX = 'api.1010ezr'
    DD_ZSF_TAGS = {
      service: 'healthcare-application',
      function: '10-10EZR async form submission'
    }.freeze
    API_KEY_PATH = 'Settings.vanotify.services.health_apps_1010.api_key'
    CALLBACK_METADATA = {
      callback_metadata: { notification_type: 'error', form_number: FORM_ID, statsd_tags: DD_ZSF_TAGS }
    }.freeze

    # retry for  2d 1h 47m 12s
    # https://github.com/sidekiq/sidekiq/wiki/Error-Handling
    sidekiq_options retry: 16

    sidekiq_retries_exhausted do |msg, _e|
      parsed_form = decrypt_form(msg['args'][0])

      StatsD.increment("#{STATSD_KEY_PREFIX}.failed_wont_retry")

      if parsed_form.present?
        PersonalInformationLog.create!(
          data: parsed_form,
          error_class: 'Form1010Ezr FailedWontRetry'
        )

        send_failure_email(parsed_form) if Flipper.enabled?(:ezr_use_va_notify_on_submission_failure)

        Form1010Ezr::Service.log_submission_failure(
          parsed_form,
          '[10-10EZR] total failure'
        )
      end
    end

    def self.decrypt_form(encrypted_form)
      JSON.parse(HealthCareApplication::LOCKBOX.decrypt(encrypted_form))
    end

    def self.send_failure_email(parsed_form)
      email = parsed_form['email']
      return if email.blank?

      first_name = parsed_form.dig('veteranFullName', 'first')
      template_id = Settings.vanotify.services.health_apps_1010.template_id.form1010_ezr_failure_email
      salutation = first_name ? "Dear #{first_name}," : ''

      VANotify::V2::QueueEmailJob.enqueue(
        email,
        template_id,
        { 'salutation' => salutation },
        API_KEY_PATH,
        CALLBACK_METADATA
      )

      StatsD.increment("#{STATSD_KEY_PREFIX}.submission_failure_email_sent")
    end

    def perform(encrypted_form, user_uuid)
      parsed_form = nil
      user = User.find(user_uuid)
      parsed_form = self.class.decrypt_form(encrypted_form)
      log_submission_start_with_attachments(parsed_form)

      submit_form(user, parsed_form)
    rescue VALIDATION_ERROR => e
      StatsD.increment("#{STATSD_KEY_PREFIX}.enrollment_system_validation_error")
      failed_guids = extract_attachment_guids(parsed_form, fallback: 'unknown')
      log_submission_failure(failed_guids, e)

      PersonalInformationLog.create!(data: parsed_form, error_class: 'Form1010Ezr EnrollmentSystemValidationFailure')
      log_validation_error(parsed_form, e)
      self.class.send_failure_email(parsed_form) if Flipper.enabled?(:ezr_use_va_notify_on_submission_failure)
    rescue Ox::ParseError => e
      log_parse_error(parsed_form, e)
      self.class.send_failure_email(parsed_form) if Flipper.enabled?(:ezr_use_va_notify_on_submission_failure)
      # The Sidekiq::JobRetry::Skip error will fail the job and not retry it
      raise Sidekiq::JobRetry::Skip
    rescue => e
      log_retryable_submission_failure(parsed_form, e)
      raise
    end

    private

    def log_validation_error(parsed_form, e)
      Form1010Ezr::Service.log_submission_failure(parsed_form, '[10-10EZR] failure')
      Rails.logger.error(e)
    end

    def log_parse_error(parsed_form, e)
      StatsD.increment("#{STATSD_KEY_PREFIX}.failed_did_not_retry")

      PersonalInformationLog.create!(data: parsed_form, error_class: 'Form1010Ezr FailedDidNotRetry')

      Rails.logger.info("Form1010Ezr FailedDidNotRetry: #{e.message}")

      Form1010Ezr::Service.log_submission_failure(parsed_form, '[10-10EZR] failure did not retry')
    end

    def log_retryable_submission_failure(parsed_form, error)
      StatsD.increment("#{STATSD_KEY_PREFIX}.async.retries")
      failed_guids = extract_attachment_guids(parsed_form, fallback: 'unknown')
      log_submission_failure(failed_guids, error)
    end

    def submit_form(user, parsed_form)
      Form1010Ezr::Service.new(user).submit_sync(parsed_form)
    end

    def extract_attachment_guids(parsed_form, fallback:)
      parsed_form&.dig('attachments')
                 &.map { |attachment| attachment['confirmationCode'] }
                 &.compact
                 &.join(',')
                 .presence || fallback
    end

    def log_submission_start_with_attachments(parsed_form)
      attachment_guids = extract_attachment_guids(parsed_form, fallback: 'none')
      log_submission_start(attachment_guids)
    end

    def log_submission_start(attachment_guids)
      correlation_id = current_correlation_id(attachment_guids)
      Rails.logger.info(
        '[HCA_SUBMISSION] 10-10EZR async submission initiated | ' \
        "correlation_id=#{correlation_id} | " \
        "attachment_guids=#{attachment_guids}"
      )
    end

    def log_submission_failure(attachment_guids, error)
      correlation_id = current_correlation_id(attachment_guids)
      Rails.logger.error(
        '[HCA_SUBMISSION_FAILED] 10-10EZR async submission failed | ' \
        "correlation_id=#{correlation_id} | " \
        "attachment_guids=#{attachment_guids} | " \
        "error_class=#{error.class.name} | " \
        "exception_class=#{error.class.name}"
      )
    end

    def current_correlation_id(fallback)
      jid.presence || fallback
    end
  end
end
