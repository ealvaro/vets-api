# frozen_string_literal: true

module ClaimsApi
  class ReportHourlyUnsuccessfulSubmissions < ClaimsApi::ServiceBase
    sidekiq_options retry: 7

    NO_INVESTIGATION_ERROR_TEXT = [
      'The Maximum number of EP codes have been reached for this benefit type claim code',
      'Claim could not be established. Retries will fail.'
    ].freeze

    RESOLVED_QUERY_BATCH_SIZE = 25
    RESOLVED_LOOKBACK_PERIOD = 14.days
    VA_GOV_CID = '0oagdm49ygCSJTp8X297'

    # rubocop:disable Metrics/MethodLength
    def perform
      return unless allow_processing?

      @search_to = 1.minute.ago
      @search_from = @search_to - 60.minutes
      @reporting_to = @search_to.in_time_zone('Eastern Time (US & Canada)').strftime('%I:%M%p %Z')
      @reporting_from = @search_from.in_time_zone('Eastern Time (US & Canada)').strftime('%I:%M%p %Z')
      @errored_claims = ClaimsApi::AutoEstablishedClaim.where(
        'status = ? AND created_at BETWEEN ? AND ? AND cid <> ?',
        'errored', @search_from, @search_to, VA_GOV_CID
      ).pluck(:id).uniq
      @va_gov_errored_claims = find_unresolved_va_gov_transaction_ids
      @errored_poa = ClaimsApi::PowerOfAttorney.where(created_at: @search_from..@search_to,
                                                      status: 'errored').pluck(:id).uniq
      @errored_itf = ClaimsApi::IntentToFile.where(created_at: @search_from..@search_to,
                                                   status: 'errored').pluck(:id).uniq
      @errored_ews = ClaimsApi::EvidenceWaiverSubmission.where(created_at: @search_from..@search_to,
                                                               status: 'errored').pluck(:id).uniq
      @environment = Rails.env
      if errored_submissions_exist?
        ClaimsApi::Slack::FailedSubmissionsMessenger.new(
          errored_disability_claims: @errored_claims,
          errored_va_gov_claims: @va_gov_errored_claims,
          errored_poa: @errored_poa,
          errored_itf: @errored_itf,
          errored_ews: @errored_ews,
          from: @reporting_from,
          to: @reporting_to,
          environment: @environment
        ).notify!
      end
    rescue ActiveRecord::QueryCanceled => e
      notify_query_timeout(e)
      raise
    end
    # rubocop:enable Metrics/MethodLength

    private

    def errored_submissions_exist?
      [@errored_claims, @va_gov_errored_claims, @errored_poa, @errored_itf, @errored_ews].any? do |collection|
        collection&.count&.positive?
      end
    end

    def allow_processing?
      Flipper.enabled? :claims_hourly_slack_error_report_enabled
    end

    def notify_query_timeout(error)
      ClaimsApi::Logger.log('claims_api_hourly_report_timeout',
                            detail: 'ReportHourlyUnsuccessfulSubmissions query timeout',
                            error: error.message)

      slack_alert_on_failure(
        'ReportHourlyUnsuccessfulSubmissions',
        "ReportHourlyUnsuccessfulSubmissions query timeout in #{Rails.env}: " \
        "#{error.message.truncate(200)}. " \
        'The job will retry automatically.'
      )
    end

    def find_unresolved_va_gov_transaction_ids
      errored_claims = fetch_errored_va_gov_claims.to_a
      return [] if errored_claims.empty?

      errored_claims.reject! do |claim|
        NO_INVESTIGATION_ERROR_TEXT.any? { |text| claim.evss_response&.to_s&.downcase&.include?(text.downcase) }
      end

      errored_transaction_ids = extract_transaction_ids_from_claims(errored_claims)
      return [] if errored_transaction_ids.empty?

      resolved_transaction_ids = find_resolved_transaction_ids(errored_transaction_ids)
      errored_transaction_ids - resolved_transaction_ids
    end

    def fetch_errored_va_gov_claims
      ClaimsApi::AutoEstablishedClaim
        .select(:id, :transaction_id, :evss_response_ciphertext, :encrypted_kms_key)
        .where(status: 'errored', cid: VA_GOV_CID, created_at: @search_from..@search_to)
    end

    def extract_transaction_ids_from_claims(claims)
      claims.map { |c| transaction_id_extracted(c.transaction_id) }.compact.uniq
    end

    def transaction_id_extracted(transaction_id)
      transaction_id&.split(',')&.first&.scan(/[a-zA-Z0-9_-]+/)&.first&.downcase
    end

    def find_resolved_transaction_ids(errored_ids)
      resolved_ids = []

      errored_ids.each_slice(RESOLVED_QUERY_BATCH_SIZE) do |batch|
        conditions_sql = batch.map { 'LOWER(transaction_id) LIKE ?' }.join(' OR ')
        condition_values = batch.map { |id| "#{ActiveRecord::Base.sanitize_sql_like(id.downcase)}%" }

        batch_results = ClaimsApi::AutoEstablishedClaim
                        .where(status: 'established', created_at: RESOLVED_LOOKBACK_PERIOD.ago..)
                        .where(conditions_sql, *condition_values)
                        .pluck(:transaction_id)

        resolved_ids.concat(batch_results.map { |id| transaction_id_extracted(id) }.compact)
      end

      resolved_ids.uniq
    end
  end
end
