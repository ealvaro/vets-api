# frozen_string_literal: true

module MedicalCopays
  module FacilityAccounts
    class LighthouseBuilder
      FACILITY_IDENTIFIER_SYSTEM = 'https://api.va.gov/services/fhir/v0/r4/NamingSystem/va-facility-identifier'
      STATION_PREFIX = 'vha_'
      ORG_CACHE_STATSD_KEY = 'api.mcp.facility_accounts.org_cache'

      def initialize(lighthouse_service:)
        @lighthouse_service = lighthouse_service
      end

      def build_facility_accounts
        # TODO: list_months entries grouped by get_station_id(invoice.facility_id),
        # nil group excluded, each group -> FacilityAccount
      end

      def build_facility_account(station_id, include_transactions: true)
        # TODO: detail fan-out for the org(s) resolving to station_id
      end

      private

      def get_station_id(org_id)
        organization = @lighthouse_service.fetch_organization(org_id, ORG_CACHE_STATSD_KEY)
        identifiers = organization&.dig('identifier') || []
        facility_identifier = identifiers.find { |identifier| identifier['system'] == FACILITY_IDENTIFIER_SYSTEM }
        facility_identifier&.dig('value')&.delete_prefix(STATION_PREFIX)&.slice(FacilityAccount::STATION_ID_PATTERN)
      end
    end
  end
end
