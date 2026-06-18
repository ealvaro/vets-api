# frozen_string_literal: true

require 'sidekiq'
require 'sidekiq/attr_package'
require_relative 'constants'
require_relative 'letter_ready_job_concern'

module EventBusGateway
  class LetterReadySmsJob
    include Sidekiq::Job
    include LetterReadyJobConcern

    STATSD_METRIC_PREFIX = 'event_bus_gateway.letter_ready_sms'

    sidekiq_options retry: Constants::SIDEKIQ_RETRY_COUNT_FIRST_SMS

    sidekiq_retry_in do |count, _exception|
      # Sidekiq default exponential backoff with jitter, plus one hour
      (count**4) + 15 + (rand(10) * (count + 1)) + 1.hour.to_i
    end

    sidekiq_retries_exhausted do |msg, _ex|
      job_id = msg['jid']
      error_class = msg['error_class']
      error_message = msg['error_message']
      cache_key = msg['args']&.[](2)
      timestamp = Time.current

      ::Rails.logger.error('LetterReadySmsJob retries exhausted',
                           { job_id:, timestamp:, error_class:, error_message: })
      tags = Constants::DD_TAGS + ["function: #{error_message}"]
      StatsD.increment("#{STATSD_METRIC_PREFIX}.exhausted", tags:)
      Sidekiq::AttrPackage.delete(cache_key) if cache_key
    end

    def perform(participant_id, template_id, cache_key = nil)
      return if sms_blocked?(participant_id, template_id, cache_key)

      icn = resolve_icn(participant_id, cache_key)

      return unless validate_sms_prerequisites(template_id, icn)

      send_sms_notification(participant_id, template_id, icn)
      StatsD.increment("#{STATSD_METRIC_PREFIX}.success", tags: Constants::DD_TAGS)

      # Clean up PII from Redis if cache_key was used
      Sidekiq::AttrPackage.delete(cache_key) if cache_key
    rescue Sidekiq::AttrPackageError => e
      # Log AttrPackage errors as application logic errors (no retries)
      Rails.logger.error('LetterReadySmsJob AttrPackage error', { error: e.message })
      raise ArgumentError, e.message
    rescue => e
      record_notification_send_failure(e, 'Sms')
      raise
    end

    private

    def sms_blocked?(participant_id, template_id, cache_key)
      if Flipper.enabled?(:event_bus_gateway_sms_blackout) && Constants.sms_blackout_period?
        if Flipper.enabled?(:event_bus_gateway_sms_blackout_defer)
          defer_sms_until_delivery_window(participant_id, template_id, cache_key)
        else
          log_sms_blackout_blocked('LetterReadySmsJob', template_id)
        end
        return true
      end

      if Flipper.enabled?(:event_bus_gateway_sms_dry_run)
        log_sms_dry_run(template_id)
        return true
      end

      false
    end

    def defer_sms_until_delivery_window(participant_id, template_id, cache_key)
      deferred_at = Constants.next_blackout_defer_time(jid)
      self.class.perform_at(deferred_at, participant_id, template_id, cache_key)
      log_sms_blackout_deferred(template_id, deferred_at)
    end

    def resolve_icn(participant_id, cache_key)
      icn = nil

      if cache_key
        attributes = Sidekiq::AttrPackage.find(cache_key)
        icn = attributes[:icn] if attributes
      end

      icn || get_icn(participant_id)
    end

    def log_sms_dry_run(template_id)
      ::Rails.logger.info(
        'LetterReadySmsJob dry run - SMS not sent',
        { notification_type: 'sms', template_id: }
      )
      StatsD.increment("#{STATSD_METRIC_PREFIX}.dry_run", tags: Constants::DD_TAGS)
    end

    def log_sms_blackout_blocked(job_name, template_id)
      ::Rails.logger.info(
        "#{job_name} blocked during SMS blackout period",
        {
          notification_type: 'sms',
          reason: 'blackout_period',
          template_id:,
          current_time_utc: Time.current.utc.iso8601
        }
      )
      tags = Constants::DD_TAGS + ['notification_type:sms', 'reason:blackout_period']
      StatsD.increment("#{STATSD_METRIC_PREFIX}.blocked", tags:)
    end

    def log_sms_blackout_deferred(template_id, deferred_at)
      ::Rails.logger.info(
        'LetterReadySmsJob deferred until SMS delivery window',
        {
          notification_type: 'sms',
          reason: 'blackout_deferred',
          template_id:,
          deferred_until_utc: deferred_at.utc.iso8601
        }
      )
      tags = Constants::DD_TAGS + ['notification_type:sms', 'reason:blackout_deferred']
      StatsD.increment("#{STATSD_METRIC_PREFIX}.blackout_deferred", tags:)
    end

    def validate_sms_prerequisites(template_id, icn)
      if icn.blank?
        log_sms_skipped('ICN not available', template_id)
        return false
      end

      true
    end

    def log_sms_skipped(reason, template_id)
      ::Rails.logger.error(
        'LetterReadySmsJob sms skipped',
        {
          notification_type: 'sms',
          reason:,
          template_id:
        }
      )
      tags = Constants::DD_TAGS + ['notification_type:sms', "reason:#{reason.parameterize.underscore}"]
      StatsD.increment("#{STATSD_METRIC_PREFIX}.skipped", tags:)
    end

    def send_sms_notification(participant_id, template_id, icn)
      response = notify_client.send_sms(
        recipient_identifier: { id_value: participant_id, id_type: 'PID' },
        template_id:,
        personalisation: {
          host: hostname_for_template
        }
      )

      create_notification_record(template_id, icn, response&.id)
    end

    def create_notification_record(template_id, icn, va_notify_id)
      notification = EventBusGatewayNotification.create(
        user_account: user_account(icn),
        template_id:,
        va_notify_id:
      )

      return if notification.persisted?

      ::Rails.logger.warn(
        'LetterReadySmsJob notification record failed to save',
        {
          errors: notification.errors.full_messages,
          template_id:,
          va_notify_id:
        }
      )
    end

    def hostname_for_template
      Constants::HOSTNAME_MAPPING[Settings.hostname] || Settings.hostname
    end

    def notify_client
      @notify_client ||= VaNotify::Service.new(
        Constants::NOTIFY_SETTINGS.api_key,
        { callback_klass: 'EventBusGateway::VANotifySmsStatusCallback' }
      )
    end
  end
end
