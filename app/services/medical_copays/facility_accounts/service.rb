# frozen_string_literal: true

module MedicalCopays
  module FacilityAccounts
    class Service
      def initialize(user)
        @user = user
      end

      def facility_accounts
        raise Common::Exceptions::Forbidden unless use_payment_history?

        facilities = builder.build_facility_accounts
        { total_current_balance: FacilityAccount.sum_balances(facilities), facilities: }
      end

      def facility_account(station_id)
        raise Common::Exceptions::Forbidden unless use_payment_history?

        builder.build_facility_account(station_id)
      end

      def statements(_station_id)
        raise Common::Exceptions::Forbidden unless use_payment_history?

        # TODO: statements representation — VBS data for all users regardless of the
        # source gate, so it lives here rather than on a builder
      end

      private

      def use_payment_history?
        MedicalCopays::FeatureFlagHelpers.facility_account_history_enabled?(@user)
      end

      def builder
        @builder ||= use_lighthouse? ? lighthouse_builder : vbs_builder
      end

      def use_lighthouse?
        MedicalCopays::FeatureFlagHelpers.lighthouse_copays_enabled?(@user)
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
