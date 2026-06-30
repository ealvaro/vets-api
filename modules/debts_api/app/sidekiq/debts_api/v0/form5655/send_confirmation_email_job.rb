# frozen_string_literal: true

require 'debts_api/v0/financial_status_report_service'
require 'sidekiq/attr_package'

module DebtsApi
  class V0::Form5655::SendConfirmationEmailJob
    include Sidekiq::Job

    FSR_STATS_KEY = 'api.form5655.send_confirmation_email'
    DIGITAL_DISPUTE_STATS_KEY = 'api.digital_dispute.send_confirmation_email'

    sidekiq_options retry: 5

    sidekiq_retries_exhausted do |job, ex|
      args = job['args'][0]
      cache_key = args['cache_key']
      submission_type = args['submission_type'] || 'fsr'
      stats_key = if submission_type == 'fsr'
                    FSR_STATS_KEY
                  else
                    DIGITAL_DISPUTE_STATS_KEY
                  end

      StatsD.increment("#{stats_key}.retries_exhausted")
      user_uuid = args['user_uuid']

      Rails.logger.error("V0::Form5655::SendConfirmationEmailJob (#{submission_type}) retries exhausted",
                         user_id: user_uuid, exception: ex)

      Sidekiq::AttrPackage.delete(cache_key) if cache_key
    end

    def perform(args)
      submission_type = args['submission_type'] || 'fsr' # TODO: make this file not fsr specific
      submissions_data = find_submissions(args['user_uuid'], submission_type)
      return if no_submissions_abort?(submission_type, args['user_uuid'], args, submissions_data)

      should_use_cache = args['user_pii'].blank?
      is_retry = args['cache_key'].present?
      pii = resolve_pii(args, should_use_cache, is_retry)
      personalisation = email_personalization_info(pii, submissions_data, submission_type)

      vanotify_cache_key = resolve_vanotify_cache_key(args['cache_key'], pii, personalisation, should_use_cache)
      identifier = pii&.dig(:email) unless should_use_cache
      options = should_use_cache ? { id_type: 'email', cache_key: vanotify_cache_key } : {}

      send_vanotify_email(identifier, args['template_id'], personalisation, options, args['user_uuid'])
      Sidekiq::AttrPackage.delete(is_retry) if is_retry
      Sidekiq::AttrPackage.delete(vanotify_cache_key) if vanotify_cache_key
    rescue Sidekiq::AttrPackageError => e
      # Log AttrPackage errors as application logic errors (no retries)
      Rails.logger.error('V0::Form5655::SendConfirmationEmailJob', { error: e.message })
      raise ArgumentError, e.message
    rescue => e
      Rails.logger.error("DebtsApi::SendConfirmationEmailJob (#{submission_type}) - Error sending email: #{e.message}")
      raise e
    end

    private

    def resolve_vanotify_cache_key(job_cache_key, pii, personalisation, should_use_cache)
      return unless should_use_cache

      # TODO: Sidekiq::AttrPackage should be created at the entry point and the cache key passed to this job.
      # rubocop:disable Cop/NoAttrPackageCreationInJob
      job_cache_key.presence || Sidekiq::AttrPackage.create(
        email: pii&.dig(:email),
        personalisation:
      )
      # rubocop:enable Cop/NoAttrPackageCreationInJob
    end

    def no_submissions_abort?(submission_type, user_uuid, args, submissions_data)
      return false if submissions_data.present?

      Rails.logger.warn(
        "DebtsApi::SendConfirmationEmailJob (#{submission_type}) - " \
        "No submissions found for user_uuid: #{user_uuid}"
      )
      Sidekiq::AttrPackage.delete(args['cache_key']) if args['cache_key']
      true
    end

    def send_vanotify_email(identifier, template_id, personalisation, options, user_uuid)
      Rails.logger.info(
        '#send_confirmation_email_job ' \
        "template_id=#{template_id} identifier_present=#{identifier.present?} user_uuid=#{user_uuid}"
      )
      DebtManagementCenter::VANotifyEmailJob.perform_async(
        identifier, template_id, personalisation, options
      )
    end

    def fetch_pii_from_cache(cache_key)
      attributes = Sidekiq::AttrPackage.find(cache_key)
      { email: attributes[:email], first_name: attributes[:first_name] } if attributes
    end

    def resolve_pii(args, should_use_cache, is_retry)
      raw = if is_retry && should_use_cache
              fetch_pii_from_cache(args['cache_key'])
            else
              args['user_pii']
            end
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
