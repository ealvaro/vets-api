# frozen_string_literal: true

require 'debts_api/v0/financial_status_report_service'

module DebtsApi
  class V0::Form5655::SendConfirmationEmailJob
    include Sidekiq::Job

    STATS_KEYS = {
      'fsr' => 'api.form5655.send_confirmation_email',
      'digital_dispute' => 'api.digital_dispute.send_confirmation_email'
    }.freeze

    def self.validated_submission_type(job_args)
      submission_type = job_args['submission_type'].presence || 'fsr'
      STATS_KEYS.fetch(submission_type)
      submission_type
    end

    sidekiq_options retry: 5

    sidekiq_retries_exhausted do |job, ex|
      args = job['args'][0]
      submission_type = validated_submission_type(args)
      stats_key = STATS_KEYS.fetch(submission_type)

      StatsD.increment("#{stats_key}.retries_exhausted")
      user_uuid = args['user_uuid']

      Rails.logger.error("V0::Form5655::SendConfirmationEmailJob (#{submission_type}) retries exhausted",
                         user_id: user_uuid, exception: ex)
    end

    def perform(args)
      submission_type = self.class.validated_submission_type(args)
      submissions_data = find_submissions(args['user_uuid'], submission_type)
      return if no_submissions_abort?(submission_type, args['user_uuid'], submissions_data)

      pii = resolve_pii(args)
      return if missing_email_abort?(submission_type, args['user_uuid'], pii)

      personalisation = email_personalization_info(pii, submissions_data, submission_type)

      send_vanotify_email(pii&.dig(:email), args, personalisation, {}, submission_type)
    rescue => e
      Rails.logger.error("DebtsApi::SendConfirmationEmailJob (#{submission_type}) - Error sending email: #{e.message}")
      raise e
    end

    private

    def no_submissions_abort?(submission_type, user_uuid, submissions_data)
      return false if submissions_data.present?

      Rails.logger.warn(
        "DebtsApi::SendConfirmationEmailJob (#{submission_type}) - " \
        "No submissions found for user_uuid: #{user_uuid}"
      )
      true
    end

    def missing_email_abort?(submission_type, user_uuid, pii)
      return false if pii&.dig(:email).present?

      Rails.logger.warn(
        "DebtsApi::SendConfirmationEmailJob (#{submission_type}) - " \
        "No email found for user_uuid: #{user_uuid}"
      )
      true
    end

    def send_vanotify_email(identifier, args, personalisation, options, submission_type)
      template_id = args['template_id']
      user_uuid = args['user_uuid']

      Rails.logger.info(
        '#send_confirmation_email_job ' \
        "template_id=#{template_id} identifier_present=#{identifier.present?} user_uuid=#{user_uuid}"
      )
      DebtManagementCenter::VANotifyEmailJob.perform_async(
        identifier, template_id, personalisation, options
      )
      stats_key = STATS_KEYS.fetch(submission_type)
      StatsD.increment("#{stats_key}.sent")
    end

    def resolve_pii(args)
      raw = args['user_pii']
      return raw unless raw.is_a?(Hash)

      raw.symbolize_keys
    end

    def email_personalization_info(pii, submissions_data, submission_type)
      confirmation_number = if submission_type == 'fsr'
                              submissions_data.map(&:id)
                            else
                              submissions_data.guid
                            end

      {
        'first_name' => pii&.dig(:first_name),
        'date_submitted' => Time.zone.now.strftime('%m/%d/%Y'),
        'confirmation_number' => confirmation_number
      }
    end

    def find_submissions(user_uuid, submission_type)
      case submission_type
      when 'digital_dispute'
        DebtsApi::V0::DigitalDisputeSubmission.where(user_uuid:, state: 1)
                                              .order(created_at: :desc).first
      else
        DebtsApi::V0::Form5655Submission.submitted.where(user_uuid:)
      end
    end
  end
end
