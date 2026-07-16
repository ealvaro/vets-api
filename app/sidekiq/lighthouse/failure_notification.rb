# frozen_string_literal: true

require 'logging/helper/data_scrubber'

class Lighthouse::FailureNotification
  include Sidekiq::Job

  NOTIFY_SETTINGS = Settings.vanotify.services.benefits_management_tools
  MAILER_TEMPLATE_ID = NOTIFY_SETTINGS.template_id.evidence_submission_failure_email

  # retry for one day
  sidekiq_options retry: 14, queue: 'low'
  # Set minimum retry time to ~1 hour
  sidekiq_retry_in do |count, _exception|
    rand(3600..3660) if count < 9
  end

  sidekiq_retries_exhausted do
    message = 'Lighthouse::FailureNotification email could not be sent'
    ::Rails.logger.info(message)
    StatsD.increment('silent_failure', tags: ['service:claim-status', "function: #{message}"])
  end

  def notify_client
    VaNotify::Service.new(
      NOTIFY_SETTINGS.api_key,
      {
        callback_klass: 'Lighthouse::EvidenceSubmissions::VANotifyEmailStatusCallback',
        callback_metadata: {
          notification_type: 'error',
          statsd_tags: { service: 'claim-status', function: 'evidence_submission_failure_email' }
        }
      }
    )
  end

  def perform(icn, personalisation)
    # NOTE: The filename in the personalisation that is passed in is obscured
    notify_client.send_email(
      recipient_identifier: { id_value: icn, id_type: 'ICN' },
      template_id: MAILER_TEMPLATE_ID,
      personalisation:
    )

    ::Rails.logger.info('Lighthouse::FailureNotification email sent')
  rescue => e
    ::Rails.logger.error('Lighthouse::FailureNotification email error',
                         scrub_pii({ message: e.message }))
    Rails.logger.error(scrub_pii(e.message))
  end

  private

  def scrub_pii(message)
    Logging::Helper::DataScrubber.scrub(message)
  end
end
