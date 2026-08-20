# frozen_string_literal: true

module MedicalCopays
  module FacilityAccounts
    class FacilityAccountSerializer
      INDEX_ATTRIBUTES = %i[
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
        {
          total_current_balance:,
          facilities: facilities.map { |account| account.as_json(only: INDEX_ATTRIBUTES) }
        }.deep_transform_keys { |key| key.to_s.camelize(:lower) }
      end
    end
  end
end
