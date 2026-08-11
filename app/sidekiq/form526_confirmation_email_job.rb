# frozen_string_literal: true

require 'va_notify/service'

class Form526ConfirmationEmailJob
  include Sidekiq::Job
  sidekiq_options expires_in: 1.day

  attr_accessor :submission

  STATSD_ERROR_NAME = 'worker.form526_confirmation_email.error'
  STATSD_SUCCESS_NAME = 'worker.form526_confirmation_email.success'

  def perform(submission_id)
    @submission = Form526Submission.find(submission_id)
    send_email
    StatsD.increment(STATSD_SUCCESS_NAME)
  rescue => e
    handle_errors(e)
    raise e if Flipper.enabled?(:form526_raise_e)
  end

  private

  def send_email
    @notify_client ||= VaNotify::Service.new(Settings.vanotify.services.va_gov.api_key)
    @template_id ||= Settings.vanotify.services.va_gov.template_id.form526_confirmation_email
    @notify_client.send_email(
      email_address: submission.veteran_email_address,
      template_id: @template_id,
      personalisation: {
        'claim_id' => submission.submitted_claim_id || '',
        'date_submitted' => submission.format_creation_time_for_mailers,
        'date_received' => format_time_for_mailers(Time.now.utc),
        'first_name' => submission.get_first_name
      }
    )
  end

  def format_time_for_mailers(time)
    time.strftime('%B %-d, %Y %-l:%M %P %Z').sub(/([ap])m/, '\1.m.')
  end

  def handle_errors(ex)
    Rails.logger.error('Form526ConfirmationEmailJob error', error: ex)
    StatsD.increment(STATSD_ERROR_NAME)
    if !Flipper.enabled?(:form526_error_handling) &&
       ex&.status_code&.between?(
         500, 599
       )
      raise ex
    end
  end
end
