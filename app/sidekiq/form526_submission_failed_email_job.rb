# frozen_string_literal: true

require 'va_notify/service'

class Form526SubmissionFailedEmailJob
  include Sidekiq::Job
  sidekiq_options expires_in: 1.day

  attr_accessor :submission

  STATSD_ERROR_NAME = 'worker.form526_submission_failed_email.error'
  STATSD_SUCCESS_NAME = 'worker.form526_submission_failed_email.success'

  def perform(submission_id, source = nil)
    @submission = Form526Submission.find(submission_id)
    send_email(source)
    StatsD.increment(STATSD_SUCCESS_NAME)
  rescue => e
    handle_errors(e)
    raise e if Flipper.enabled?(:form526_raise_e)
  end

  private

  def send_email(source)
    @notify_client ||= VaNotify::Service.new(Settings.vanotify.services.va_gov.api_key)
    @template_id ||= Settings.vanotify.services.va_gov.template_id.form526_submission_failed_email
    @notify_client.send_email(
      email_address: submission.veteran_email_address,
      template_id: @template_id,
      personalisation: {
        'claim_id' => submission.submitted_claim_id || '',
        'date_submitted' => submission.format_creation_time_for_mailers,
        'first_name' => first_name_for_personalization(source)
      }
    )
  end

  def first_name_for_personalization(source)
    if source == 'pif'
      submission.get_first_name&.capitalize || 'Sir or Madam'
    else
      submission.get_first_name
    end
  end

  def handle_errors(ex)
    Rails.logger.error('Form526SubmissionFailedEmailJob error', error: ex)
    StatsD.increment(STATSD_ERROR_NAME)
    if !Flipper.enabled?(:form526_error_handling) && ex.respond_to?(:status_code) && ex.status_code.between?(500,
                                                                                                             599)
      raise ex
    end
  end
end
