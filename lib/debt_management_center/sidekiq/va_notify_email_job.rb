# frozen_string_literal: true

require 'logging/helper/data_scrubber'

module DebtManagementCenter
  class VANotifyEmailJob
    include Sidekiq::Job
    sidekiq_options retry: 14
    STATS_KEY = 'api.dmc.va_notify_email'
    LOCKBOX = Lockbox.new(key: Settings.lockbox.master_key, encode: true)
    VA_NOTIFY_CALLBACK_OPTIONS = {
      callback_metadata: {
        notification_type: 'error',
        form_number: DebtsApi::V0::Form5655Submission::FORM_ID,
        statsd_tags: {
          service: DebtsApi::V0::Form5655Submission::ZSF_DD_TAG_SERVICE,
          function: DebtsApi::V0::Form5655Submission::ZSF_DD_TAG_FUNCTION
        }.freeze
      }.freeze
    }.freeze

    def self.scrub_pii(message)
      Logging::Helper::DataScrubber.scrub(message)
    end

    class UnrecognizedIdentifier < StandardError; end

    sidekiq_retries_exhausted do |job, ex|
      options = (job['args'][3] || {}).transform_keys(&:to_s)

      StatsD.increment("#{STATS_KEY}.retries_exhausted")
      if options['failure_mailer'] == true
        StatsD.increment("#{DebtsApi::V0::Form5655Submission::STATS_KEY}.send_failed_form_email.failure")
        StatsD.increment('silent_failure', tags: %w[service:debt-resolution function:sidekiq_retries_exhausted])
      end
      Rails.logger.error('VANotifyEmailJob retries exhausted', scrub_pii(exception: ex))
    end

    def perform(identifier, template_id, personalisation = nil, options = {})
      Rails.logger.info("#va_notify_email_job identifier_present=#{identifier.present?}")
      options = (options || {}).transform_keys(&:to_s)

      send_email(identifier, template_id, personalisation, options)
      record_success(options['failure_mailer'])
    rescue => e
      handle_error(e, template_id)
    end

    private

    def send_email(identifier, template_id, personalisation, options)
      notify_client = va_notify_client(options['failure_mailer'])
      notify_client.send_email(email_params(identifier, template_id, personalisation, options))
    end

    def record_success(use_failure_mailer)
      if use_failure_mailer == true
        StatsD.increment("#{DebtsApi::V0::Form5655Submission::STATS_KEY}.send_failed_form_email.success")
      end

      StatsD.increment("#{STATS_KEY}.success")
    end

    def handle_error(error, template_id)
      StatsD.increment("#{STATS_KEY}.failure")
      # Do not log error.message - it may contain PII (email, personalisation) from API responses
      Rails.logger.error("DebtManagementCenter::VANotifyEmailJob failed to send email: #{error.class}")
      Rails.logger.error(scrub_pii(error.message), { args: { template_id: }, error: :dmc_va_notify_email_job })
      raise error
    end

    def email_params(identifier, template_id, personalisation, options)
      id_type = options['id_type'] || 'email'
      identifier, personalisation = plain_pii(identifier, personalisation)

      case id_type.downcase
      when 'email'
        {
          email_address: identifier,
          template_id:,
          personalisation:
        }.compact
      when 'icn'
        {
          recipient_identifier: { id_value: identifier, id_type: 'ICN' },
          template_id:,
          personalisation:
        }.compact
      else
        raise UnrecognizedIdentifier, id_type
      end
    end

    def plain_pii(identifier, personalisation)
      [plain_value(identifier), plain_personalisation(personalisation)]
    end

    def plain_personalisation(personalisation)
      return personalisation if personalisation.blank?

      personalisation.merge(
        personalisation.slice('first_name', 'name').transform_values { |value| plain_value(value) }
      )
    end

    def plain_value(value)
      return value if value.blank?

      LOCKBOX.decrypt(value)
    rescue ActiveSupport::MessageEncryptor::InvalidMessage, Lockbox::DecryptionError
      value
    end

    def va_notify_client(use_failure_mailer)
      if use_failure_mailer == true
        VaNotify::Service.new(Settings.vanotify.services.dmc.api_key, VA_NOTIFY_CALLBACK_OPTIONS)
      else
        VaNotify::Service.new(Settings.vanotify.services.dmc.api_key)
      end
    end

    def scrub_pii(message)
      Logging::Helper::DataScrubber.scrub(message)
    end
  end
end
