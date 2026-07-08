# frozen_string_literal: true

module VAOS
  module V2
    ##
    # Non-blocking observability for incomplete CCRA referral payloads served by
    # {VAOS::V2::ReferralsController}. Emits error-level logs and StatsD counters
    # when scheduling-critical fields are blank. Does not alter the HTTP response.
    #
    # Field rules match the referral-data validation the EPS scheduling flow
    # uses to block draft creation; this monitor only records gaps at
    # list/detail read time.
    #
    class ReferralMissingDataMonitor
      include VAOS::CommunityCareConstants

      LIST_METRIC = "#{STATSD_PREFIX}.referral_list.missing_data".freeze
      DETAIL_METRIC = "#{STATSD_PREFIX}.referral_detail.missing_data".freeze
      REFERRING_FACILITY_CODE_FIELD = 'referring_facility_code'
      REFERRAL_PROVIDER_NPI_FIELD = 'referral_provider_npi'

      LIST_LOG_MESSAGE = "#{CC_APPOINTMENTS}: Referral list: Missing referral data".freeze
      DETAIL_LOG_MESSAGE = "#{CC_APPOINTMENTS}: Referral detail: Missing referral data".freeze

      def self.log_list(referrals, user:)
        new(user).log_list(referrals)
      end

      def self.log_detail(referral, user:)
        new(user).log_detail(referral)
      end

      def initialize(user)
        @user = user
      end

      # @param referrals [Array<Ccra::ReferralListEntry>] The collection of referrals
      # @return [void]
      def log_list(referrals)
        return unless referrals.respond_to?(:each)

        referrals.each do |referral|
          log_missing_fields(
            referral:,
            missing_fields: missing_list_fields(referral),
            log_message: LIST_LOG_MESSAGE,
            metric: LIST_METRIC
          )
        end
      end

      # @param referral [Ccra::ReferralDetail] the referral response object
      # @return [void]
      def log_detail(referral)
        log_missing_fields(
          referral:,
          missing_fields: missing_detail_fields(referral),
          log_message: DETAIL_LOG_MESSAGE,
          metric: DETAIL_METRIC
        )
      end

      private

      attr_reader :user

      def log_missing_fields(referral:, missing_fields:, log_message:, metric:)
        return if missing_fields.empty?

        station_id = sanitize_log_value(referral.station_id)
        Rails.logger.error(
          log_message,
          {
            missing_data: missing_fields,
            station_id:,
            user_uuid: user.uuid
          }
        )
        StatsD.increment(metric, tags: [
                           COMMUNITY_CARE_SERVICE_TAG,
                           "station_id:#{station_id}"
                         ])
      end

      # @param referral [Ccra::ReferralListEntry, Ccra::ReferralDetail]
      # @return [Array<String>] snake_case field names that are blank
      def missing_list_fields(referral)
        missing = []
        missing << 'category_of_care' if referral.category_of_care.blank?
        missing << 'expiration_date' if referral.expiration_date.blank?
        missing << 'referral_number' if referral.referral_number.blank?
        missing << 'referral_consult_id' if referral.referral_consult_id.blank?
        missing << 'station_id' if referral.station_id.blank?
        missing
      end

      # @param referral [Ccra::ReferralDetail]
      # @return [Array<String>] snake_case field names that are blank
      def missing_detail_fields(referral)
        missing = missing_list_fields(referral)
        missing << 'referral_date' if referral.referral_date.blank?
        missing << REFERRING_FACILITY_CODE_FIELD if referral.referring_facility_code.blank?
        missing << REFERRAL_PROVIDER_NPI_FIELD if referral.provider_npi.blank?
        missing
      end

      def sanitize_log_value(value)
        return 'no_value' if value.blank?

        value.to_s.gsub(/\s+/, '_')
      end
    end
  end
end
