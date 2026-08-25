# frozen_string_literal: true

module MedicalCopays
  module FacilityAccounts
    # Mailed monthly copay statement — the document as printed, distinct from the live
    # ledger (FacilityAccount).
    # Contract: GET /v1/medical-copays/facilities/{station_id}/statements
    class Statement
      include Vets::Model

      attribute :id, String
      attribute :station_id, String
      attribute :facility_name, String
      attribute :account_number, String
      attribute :facility_address, Hash
      attribute :recipient_address, Hash
      attribute :statement_date, Date
      attribute :pay_by_date, Date
      attribute :previous_balance, Float
      attribute :new_charges, Float
      attribute :payments_and_credits, Float
      attribute :statement_balance, Float
      attribute :line_items, Hash, array: true
    end
  end
end
