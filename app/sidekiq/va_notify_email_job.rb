# frozen_string_literal: true

require 'logging/helper/data_scrubber'

###########################################################################################
# This class is deprecated in favor of modules/va_notify/app/sidekiq/va_notify/email_job.rb
# Use that one instead.
###########################################################################################
# TODO: Remove this class
class VANotifyEmailJob
  include Sidekiq::Job
  # retry for  2d 1h 47m 12s
  # https://github.com/sidekiq/sidekiq/wiki/Error-Handling
  sidekiq_options retry: 16

  def perform(email, template_id, personalisation = nil)
    notify_client = VaNotify::Service.new(Settings.vanotify.services.va_gov.api_key)

    notify_client.send_email(
      **{
        email_address: email,
        template_id:,
        personalisation:
      }.compact
    )
  rescue VANotify::Error => e
    if e.status_code == 400
      Rails.logger.error(scrub_pii(e.message),
                         scrub_pii({ args: { template_id:, personalisation: } }.merge({ error: :va_notify_email_job })))
    else
      raise e
    end
  end

  private

  def scrub_pii(message)
    Logging::Helper::DataScrubber.scrub(message)
  end
end
