# frozen_string_literal: true

module MedicalCopays
  module FacilityAccounts
    class Service
      def initialize(user)
        @user = user
      end

      def accounts
        raise Common::Exceptions::Forbidden unless use_payment_history?

        facilities = builder.build_facility_accounts
        { total_current_balance: FacilityAccount.sum_balances(facilities), facilities: }
      end

      def account(station_id, include_transactions: true)
        raise Common::Exceptions::Forbidden unless use_payment_history?

        builder.build_facility_account(station_id, include_transactions:)
      end

      def statements(_station_id)
        raise Common::Exceptions::Forbidden unless use_payment_history?

        # TODO: statements representation — VBS data for all users regardless of the
        # source gate, so it lives here rather than on a builder
      end

      private

      def use_payment_history?
        Flipper.enabled?(:enable_copays_payment_history, @user)
      end

      def builder
        @builder ||= use_lighthouse? ? lighthouse_builder : vbs_builder
      end

      # TODO: flag-logic ticket — Cerner users stay on VBS regardless of this flag, and
      # V1::MedicalCopaysController#use_vbs? is being reworked around the same flag pair;
      # the two gates must land aligned
      def use_lighthouse?
        Flipper.enabled?(:enable_lighthouse_copays, @user)
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
