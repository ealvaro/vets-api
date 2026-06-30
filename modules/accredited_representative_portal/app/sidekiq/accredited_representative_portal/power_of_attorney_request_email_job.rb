# frozen_string_literal: true

require 'logging/helper/data_scrubber'

module AccreditedRepresentativePortal
  class PowerOfAttorneyRequestEmailJob
    include Sidekiq::Job
    sidekiq_options retry: 14 # The retry logic here matches VANotify::EmailJob.

    sidekiq_retries_exhausted do |msg, _ex|
      job_id = msg['jid']
      job_class = msg['class']
      error_class = msg['error_class']
      error_message = msg['error_message']

      message = "#{job_class} retries exhausted"
      Rails.logger.error(message, Logging::Helper::DataScrubber.scrub({ job_id:, error_class:, error_message: }))
      StatsD.increment("sidekiq.jobs.#{job_class.underscore}.retries_exhausted")
    end

    def perform(poa_request_notification_id,
                personalisation = nil,
                api_key = Settings.vanotify.services.va_gov.api_key)
      poa_request_notification = PowerOfAttorneyRequestNotification.find(poa_request_notification_id)
      notify_client = VaNotify::Service.new(api_key, email_delivery_callback(poa_request_notification.type))
      template_id = poa_request_notification.template_id

      response = notify_client.send_email(
        {
          email_address: poa_request_notification.email_address,
          template_id:,
          personalisation: generate_personalisation(poa_request_notification) || personalisation
        }.compact
      )
      poa_request_notification.update!(notification_id: response.id)
    rescue VANotify::Error => e
      handle_backend_exception(e, template_id)
    end

    def handle_backend_exception(e, template_id)
      if e.status_code == 400
        context = {
          args: { template_id: }
        }.merge({ error: :accredited_representative_portal_power_of_attorney_request_email_job })

        Rails.logger.error(scrub_pii(e.message), scrub_pii(context))
      else
        raise e
      end
    end

    private

    def scrub_pii(message)
      Logging::Helper::DataScrubber.scrub(message)
    end

    def generate_personalisation(notification)
      case [notification.type, notification.recipient_type]
      in ['requested', _recipient_type]
        EmailPersonalisations::Requested
      in ['declined', _recipient_type]
        EmailPersonalisations::Declined
      in ['expiring', _recipient_type]
        EmailPersonalisations::Expiring
      in ['expired', _recipient_type]
        EmailPersonalisations::Expired
      in ['enqueue_failed' | 'submission_failed', 'claimant']
        EmailPersonalisations::FailedClaimant
      in ['enqueue_failed' | 'submission_failed', 'resolver']
        EmailPersonalisations::FailedRep
      else
        raise "Unsupported notification type=#{notification.type} recipient_type=#{notification.recipient_type}"
      end.generate(notification)
    end

    def email_delivery_callback(type)
      {
        callback_klass: 'AccreditedRepresentativePortal::EmailDeliveryStatusCallback',
        callback_metadata: {
          statsd_tags: {
            service: 'accredited-representative-portal',
            function: "poa_request_#{type}_email"
          }
        }
      }
    end
  end
end
