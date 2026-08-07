# frozen_string_literal: true

module MedicalCopays
  module FacilityAccounts
    class FacilityAccount
      include Vets::Model

      STATION_ID_PATTERN = /\A\d{3}/
      PAYMENT_DUE_DAYS = 25

      def self.sum_balances(items)
        items.reduce(0.to_d) do |sum, item|
          sum + item.current_balance.to_d
        end.to_f
      end

      attribute :station_id, String
      attribute :facility_name, String
      attribute :is_cerner, Bool
      attribute :account_number, String
      attribute :current_balance, Float
      attribute :past_due_balance, Float
      attribute :statement_date, Date
      attribute :due_date, Date
      attribute :transactions, Hash, array: true
    end
  end
end
