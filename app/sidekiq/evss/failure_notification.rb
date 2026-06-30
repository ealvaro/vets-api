# frozen_string_literal: true

require 'logging/helper/data_scrubber'

class EVSS::FailureNotification
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
    ::Rails.logger.info('EVSS::FailureNotification email could not be sent')
  end

  def notify_client
    VaNotify::Service.new(NOTIFY_SETTINGS.api_key, { callback_klass: 'BenefitsDocuments::VANotifyEmailStatusCallback' })
  end

  def perform(icn, personalisation)
    # NOTE: The file_name in the personalisation that is passed in is obscured
    notify_client.send_email(
      recipient_identifier: { id_value: icn, id_type: 'ICN' },
      template_id: MAILER_TEMPLATE_ID,
      personalisation:
    )

    ::Rails.logger.info('EVSS::FailureNotification email sent')
  rescue => e
    ::Rails.logger.error('EVSS::FailureNotification email error',
                         scrub_pii({ message: e.message }))
  end

  private

  def scrub_pii(message)
    Logging::Helper::DataScrubber.scrub(message)
  end
end
