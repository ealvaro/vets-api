# frozen_string_literal: true

require 'medical_copays/cerner_facilities'

module MedicalCopays
  module FacilityAccounts
    class Service
      STATSD_KEY_PREFIX = 'api.mcp.facility_accounts'
      # Lighthouse raises Common::Exceptions off ServiceException::ERROR_MAP, so its 502/503/504
      # already read as upstream. Only the 500 mapping needs translating.
      LIGHTHOUSE_UPSTREAM_500 = Common::Exceptions::ExternalServerInternalServerError
      UPSTREAM_SERVICE_ERRORS = [
        LIGHTHOUSE_UPSTREAM_500,
        MedicalCopays::VBS::Service::ServiceError
      ].freeze

      def initialize(user)
        @user = user
      end

      def facility_accounts(status: nil)
        require_payment_history!

        facilities = with_metrics(:index) { builder.build_facility_accounts(status:) }
        { total_current_balance: FacilityAccount.sum_balances(facilities), facilities: }
      end

      def facility_account(station_id)
        require_payment_history!

        account = with_metrics(:show) { builder.build_facility_account(station_id) }
        record_missing_account(station_id) if account.nil?
        account
      end

      def statements(_station_id)
        require_payment_history!

        # TODO: statements representation — VBS data for all users regardless of the
        # source gate, so it lives here rather than on a builder
      end

      private

      def with_metrics(action, &)
        result = StatsD.measure("#{STATSD_KEY_PREFIX}.#{action}.latency", tags: statsd_tags, &)
        StatsD.increment("#{STATSD_KEY_PREFIX}.#{action}.success", tags: statsd_tags)
        result
      rescue => e
        StatsD.increment("#{STATSD_KEY_PREFIX}.#{action}.failure",
                         tags: statsd_tags + ["error:#{e.class.to_s.delete(':')}"])
        raise unless UPSTREAM_SERVICE_ERRORS.any? { |error_class| e.is_a?(error_class) }

        Rails.logger.error('MedicalCopays::FacilityAccounts upstream service error',
                           error_class: e.class.name, user_uuid: @user.uuid)
        raise Common::Exceptions::BadGateway
      end

      def record_missing_account(station_id)
        StatsD.increment("#{STATSD_KEY_PREFIX}.show.not_found", tags: statsd_tags)
        Rails.logger.warn('MedicalCopays::FacilityAccounts no account found',
                          station_id:, user_uuid: @user.uuid)
      end

      def require_payment_history!
        return if use_payment_history?

        StatsD.increment("#{STATSD_KEY_PREFIX}.gate.backstop_tripped")
        raise Common::Exceptions::Forbidden
      end

      def use_payment_history?
        MedicalCopays::FeatureFlagHelpers.facility_account_history_enabled?(@user)
      end

      def use_lighthouse?
        return @use_lighthouse if defined?(@use_lighthouse)

        @use_lighthouse = MedicalCopays::FeatureFlagHelpers.lighthouse_copays_enabled?(@user) && !cerner_copay_user?
      end

      def builder
        @builder ||= use_lighthouse? ? lighthouse_builder : vbs_builder
      end

      def statsd_tags
        @statsd_tags ||= ["source:#{use_lighthouse? ? 'lighthouse' : 'vbs'}"]
      end

      def cerner_copay_user?
        MedicalCopays::CernerFacilities.cerner_copay_user?(@user)
      end

      def lighthouse_builder
        @lighthouse_builder ||= LighthouseBuilder.new(
          lighthouse_service: MedicalCopays::LighthouseIntegration::Service.new(@user.icn)
        )
      end

      def vbs_builder
        @vbs_builder ||= VBSBuilder.new(vbs_service: MedicalCopays::VBS::Service.build(user: @user))
      end
    end
  end
end
