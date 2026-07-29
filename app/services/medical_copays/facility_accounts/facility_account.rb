# frozen_string_literal: true

module MedicalCopays
  module FacilityAccounts
    class FacilityAccount
      include Vets::Model

      STATION_ID_PATTERN = /\A\d{3}/
      PAYMENT_DUE_DAYS = 25

      def self.sum_balances(items)
        items.reduce(BigDecimal('0')) do |sum, item|
          sum + BigDecimal(item.current_balance.to_s)
        end.to_f
      end

      attribute :station_id, String
      attribute :facility_name, String
      attribute :is_cerner, Bool
      attribute :current_balance, Float
      attribute :past_due_balance, Float
      attribute :statement_date, Date
      attribute :due_date, Date
    end
  end
end
