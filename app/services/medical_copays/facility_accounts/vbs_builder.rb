# frozen_string_literal: true

module MedicalCopays
  module FacilityAccounts
    class VBSBuilder
      def initialize(vbs_service:)
        @vbs_service = vbs_service
      end

      def build_facility_accounts
        # TODO: get_copays statements grouped by get_station_id(statement),
        # latest statement per facility -> FacilityAccount
      end

      def build_facility_account(station_id, include_transactions: true)
        # TODO: latest-statement snapshot for station_id
      end

      private

      def get_station_id(statement)
        statement['pSFacilityNum'].to_s.slice(FacilityAccount::STATION_ID_PATTERN)
      end
    end
  end
end
