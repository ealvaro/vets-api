# frozen_string_literal: true

# Invoke this as follows:
#   rails simple_forms_api:send_expiration_emails
#
# Finds successful 40-1330M form submissions whose expiration date has passed
# (30 days after submission) and enqueues a VANotify expiration
# email to the applicant, scheduled for 9 AM ET the next day.
# Idempotency is ensured via form_submissions.expiration_email_sent_at.
module SimpleFormsApi
  module SendExpirationEmailsTaskLogging
    module_function

    def log_results(enqueued, errors)
      Rails.logger.info 'SendExpirationEmails: Complete',
                        enqueued_count: enqueued.count,
                        error_count: errors.count
    end

    def log_errors(errors)
      errors.each do |error|
        Rails.logger.error 'SendExpirationEmails error',
                           form_submission_id: error[:form_submission_id],
                           message: error[:message],
                           backtrace: error[:backtrace]
      end
    end
  end

  module SendExpirationEmailsTaskHelpers
    module_function

    def latest_confirmation_number(form_submission)
      form_submission.form_submission_attempts
                     .where(aasm_state: %w[success vbms])
                     .where.not(benefits_intake_uuid: nil)
                     .order(created_at: :asc)
                     .last
                     &.benefits_intake_uuid
    end

    def extract_applicant_email(form_submission)
      form_data = JSON.parse(form_submission.form_data)
      form_data['applicantEmail'] || form_data.dig('applicant', 'email')
    rescue JSON::ParserError
      nil
    end
  end

  module SendExpirationEmailsTask
    module_function

    def run
      submissions = fetch_expired_submissions
      Rails.logger.info 'SendExpirationEmails: Total expired submissions found', count: submissions.count
      enqueued, errors = process_expired_submissions(submissions)
      SimpleFormsApi::SendExpirationEmailsTaskLogging.log_results(enqueued, errors)
    end

    def expiration_email_sent_at_column_present?
      FormSubmission.connection.column_exists?(:form_submissions, :expiration_email_sent_at)
    end

    def fetch_expired_submissions
      unless expiration_email_sent_at_column_present?
        Rails.logger.info(
          'SendExpirationEmails: Skipping - expiration_email_sent_at column not present on form_submissions'
        )
        return FormSubmission.none
      end

      expiration_cutoff = 30.days.ago

      FormSubmission
        .joins(:form_submission_attempts)
        .where(form_type: '40-1330M')
        .where(expiration_email_sent_at: nil)
        .where(form_submissions: { created_at: ..expiration_cutoff })
        .where(form_submission_attempts: { aasm_state: %w[success vbms] })
        .where.not(form_submission_attempts: { benefits_intake_uuid: nil })
        .distinct
    end

    def process_expired_submissions(submissions)
      enqueued = []
      errors = []

      submissions.each do |form_submission|
        did_enqueue = enqueue_expiration_email(form_submission)
        next unless did_enqueue

        # expiration_email_sent_at marks the submission as processed immediately after enqueueing
        # (the email itself is scheduled for 9 AM ET). This prevents re-sending on subsequent
        # task runs even though the email hasn't been physically delivered yet.
        #
        # This column is introduced in a separate migration PR, so we only update it when present.
        form_submission.update!(expiration_email_sent_at: Time.current) if expiration_email_sent_at_column_present?

        enqueued << form_submission.id
        Rails.logger.info 'SendExpirationEmails: Enqueued expiration email', form_submission_id: form_submission.id
      rescue => e
        errors << { form_submission_id: form_submission.id, message: e.message, backtrace: e.backtrace }
        Rails.logger.error 'SendExpirationEmails: Error enqueuing expiration email',
                           form_submission_id: form_submission.id,
                           message: e.message
      end

      SimpleFormsApi::SendExpirationEmailsTaskLogging.log_errors(errors)
      [enqueued, errors]
    end

    def enqueue_expiration_email(form_submission)
      # We purposely avoid marking/recording a submission as "enqueued" unless we pass
      # basic preconditions that indicate an email will actually be queued.
      #
      # NOTE: `SimpleFormsApi::Notification::Email#send` can return early (flipper disabled,
      # template_id missing) or do nothing when there is no recipient/user_account. These
      # checks prevent us from permanently suppressing future sends by incorrectly setting
      # expiration_email_sent_at.
      recipient_email = SimpleFormsApi::SendExpirationEmailsTaskHelpers.extract_applicant_email(form_submission)
      return false if recipient_email.blank?

      confirmation_number = SimpleFormsApi::SendExpirationEmailsTaskHelpers.latest_confirmation_number(form_submission)
      return false if log_and_skip_missing_confirmation_number(form_submission, confirmation_number)

      enqueue_result = send_expiration_email(form_submission, confirmation_number, recipient_email)
      enqueue_result.present?
    end

    def send_expiration_email(form_submission, confirmation_number, recipient_email)
      SimpleFormsApi::Notification::Email.new(
        {
          form_data: JSON.parse(form_submission.form_data),
          form_number: 'vba_40_1330m',
          confirmation_number:,
          date_submitted: form_submission.created_at.strftime('%B %d, %Y'),
          expiration_date: expiration_date(form_submission),
          email: recipient_email
        },
        notification_type: :expiration,
        user_account: form_submission.user_account
      ).send(at: time_to_send)
    end

    def time_to_send
      now = Time.current.in_time_zone('Eastern Time (US & Canada)')
      now.tomorrow.change(hour: 9, min: 0)
    end

    def expiration_date(form_submission)
      # expiration_date is computed from the submission's created_at so it matches the
      # 30-day threshold used to select submissions in fetch_expired_submissions.
      (form_submission.created_at + 30.days).strftime('%B %d, %Y')
    end

    def log_and_skip_missing_confirmation_number(form_submission, confirmation_number)
      return false if confirmation_number.present?

      Rails.logger.info(
        'SendExpirationEmails: Skipping - missing confirmation_number',
        form_submission_id: form_submission.id
      )
      true
    end
  end
end

namespace :simple_forms_api do
  task send_expiration_emails: :environment do
    SimpleFormsApi::SendExpirationEmailsTask.run
  end
end
