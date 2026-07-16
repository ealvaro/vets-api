# frozen_string_literal: true

module MedicalCopays
  module FacilityAccounts
    class FacilityAccount
      include Vets::Model

      STATION_ID_PATTERN = /\A\d{3}/

      attribute :station_id, String
    end
  end
end
