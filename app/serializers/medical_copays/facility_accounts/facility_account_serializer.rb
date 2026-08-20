# frozen_string_literal: true

module MedicalCopays
  module FacilityAccounts
    class FacilityAccountSerializer
      ATTRIBUTES = %i[
        station_id
        facility_name
        is_cerner
        account_number
        current_balance
        past_due_balance
        statement_date
        due_date
        transactions
      ].freeze

      def self.index(total_current_balance:, facilities:)
        camelize(
          { total_current_balance:,
            facilities: facilities.map { |account| account.as_json(only: ATTRIBUTES) } }
        )
      end

      def self.show(facility_account)
        camelize(facility_account.as_json(only: ATTRIBUTES))
      end

      def self.camelize(payload)
        payload.deep_transform_keys { |key| key.to_s.camelize(:lower) }
      end
      private_class_method :camelize
    end
  end
end
