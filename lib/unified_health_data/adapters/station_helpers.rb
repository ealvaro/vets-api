# frozen_string_literal: true

require_relative '../facility_service'
require_relative 'facility_name_resolver'

module UnifiedHealthData
  module Adapters
    # Station number extraction and facility resolution utilities for FHIR resources.
    # Extracted from FhirHelpers to provide focused facility/station functionality.
    #
    # Handles extraction from multiple data sources:
    # - Oracle Health: Practitioner identifiers (SN=XXX format or 3-digit OTHER type)
    # - VistA via UHD: Organization identifiers with VA OID system
    module StationHelpers
      VA_STATION_OID = 'urn:oid:2.16.840.1.113883.4.349'

      # Extract station number from a record's contained resources.
      # Used by Service layer for cache pre-warming.
      #
      # @param record [Hash] A UHD record with 'resource' > 'contained'
      # @return [String, nil] Station number or nil if not found
      def extract_station_number_from_record(record)
        return nil if record.nil?

        contained = record.dig('resource', 'contained')
        extract_station_number(contained)
      end

      # Resolves a facility name from an Organization resource's station number.
      #
      # @param organization [Hash] A FHIR Organization resource
      # @return [String, nil] Facility name or nil if not found
      def resolve_hostname_location(organization)
        identifier = organization&.dig('identifier')&.find { |id| id['system'] == VA_STATION_OID }
        station_number = identifier&.dig('value')
        return nil if station_number.blank?

        facility_name_resolver.lookup(station_number)
      rescue => e
        Rails.logger.warn(
          'Failed to resolve facility name for hostname location ' \
          "(organization_id=#{organization['id']}, station_number=#{station_number}, " \
          "error_class=#{e.class}): #{e.message}",
          {
            service: 'unified_health_data',
            organization_id: organization['id'],
            station_number:,
            error_class: e.class.to_s
          }
        )
        nil
      end

      # Extracts station number from contained resources using multiple fallback strategies
      # Fallback chain:
      #   1. Practitioner SN=XXX format (most explicit, Oracle Health)
      #   2. Practitioner plain 3-digit number with "OTHER" type (Oracle Health)
      #   3. Organization with VA OID system (VistA data via UHD)
      #
      # @param contained [Array<Hash>] Array of contained FHIR resources
      # @return [String, nil] Station number (e.g., '668') or nil if not found
      def extract_station_number(contained)
        return nil if contained.blank?

        # Try Practitioner identifiers first (Oracle Health data)
        station_number = extract_station_from_practitioner(contained)
        return station_number if station_number.present?

        # Fallback: Try Organization identifiers (VistA data via UHD)
        extract_station_from_organization(contained)
      end

      # Extracts station number from Practitioner identifiers
      # Used primarily for Oracle Health data
      # Priority: SN=XXX format > plain 3-digit with OTHER type
      #
      # @param contained [Array<Hash>] Array of contained FHIR resources
      # @return [String, nil] Station number or nil if not found
      def extract_station_from_practitioner(contained)
        practitioner = contained.find { |r| r['resourceType'] == 'Practitioner' }
        return nil unless practitioner&.dig('identifier')

        identifiers = practitioner['identifier']

        # Priority 1: SN=XXX format (most explicit)
        sn_identifier = identifiers.find { |i| (val = i['value']).present? && val.start_with?('SN=') }
        return sn_identifier['value'].sub('SN=', '') if sn_identifier

        # Priority 2: Station number with "OTHER" type (3 digits, optionally with letter suffix like 668A, 668GC)
        plain_identifier = identifiers.find do |i|
          (val = i['value']).present? && i.dig('type', 'text') == 'OTHER' && val.match?(/^\d{3}[A-Z]{0,2}$/i)
        end
        plain_identifier&.dig('value')
      end

      # Extracts station number from Organization identifiers
      # Used primarily for VistA data coming through UHD
      # Looks for identifiers with the VA OID system (urn:oid:2.16.840.1.113883.4.349)
      #
      # @param contained [Array<Hash>] Array of contained FHIR resources
      # @return [String, nil] Station number or nil if not found
      def extract_station_from_organization(contained)
        organization = contained.find { |r| r['resourceType'] == 'Organization' }
        return nil unless organization&.dig('identifier')

        organization['identifier'].each do |identifier|
          system = identifier['system']
          value = identifier['value']

          # VA OID system identifier contains station number
          # Example: {"system": "urn:oid:2.16.840.1.113883.4.349", "value": "989"}
          next unless system.to_s.include?('2.16.840.1.113883.4.349') && value.present?

          return value
        end

        nil
      end

      private

      def facility_service
        @facility_service ||= UnifiedHealthData::FacilityService.new
      end

      def facility_name_resolver
        @facility_name_resolver ||= UnifiedHealthData::Adapters::FacilityNameResolver.new
      end
    end
  end
end
