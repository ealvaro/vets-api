# frozen_string_literal: true

module VAOS
  module V2
    module Unified
      # Represents a single VA schedulable clinic (clinic IEN) at a Lighthouse facility.
      # +id+ is the clinic IEN. +location_id+ is the parent facility +unique_id+ used with VAOS
      # clinics and slots APIs.
      class VAProvider < BaseProvider
        # Lighthouse facility_type values that identify Cerner / Oracle Health VA sites.
        # All other VA medical facilities are treated as VistA-backed for scheduling purposes.
        CERNER_FACILITY_TYPES = %w[va_cerner_facility].freeze

        # +facility_id+ is the untranslated Lighthouse composite id (e.g. "vha_630"),
        # kept distinct from +location_id+ (the VAOS-facing station) so drive-time
        # enrichment can join against the VA Facilities +nearby+ response, which keys
        # bands by that composite id.
        attr_accessor :location_id, :facility_id, :facility_type, :service_type

        def initialize(attrs = {})
          super
          self.provider_type = 'va'
        end

        ##
        # Cerner / Oracle Health VA sites accept +clinicalService+ as a slot-search filter on VPG;
        # VistA sites reject it (HTTP 400 "Service Type cannot be used as a filter for VistA sites").
        # Callers fetching VA slots use this to decide whether to forward +clinical_service+.
        def cerner?
          CERNER_FACILITY_TYPES.include?(facility_type.to_s)
        end

        ##
        # @param facility [FacilitiesApi::V2::Lighthouse::Facility] parent facility (address, geo, phone).
        #   Callers should set +facility.unique_id+ to the VAOS-facing station (e.g. unified search
        #   applies {VAOS::V2::Unified::FacilityIdTranslator} before building providers).
        # @param clinic [OpenStruct, Hash] VAOS clinic payload from SystemsService#get_facility_clinics
        #
        def self.from_facility_and_clinic(facility, clinic, service_type: nil)
          clinic = clinic.to_h if clinic.is_a?(OpenStruct)

          new(
            id: clinic[:id],
            location_id: facility.unique_id,
            facility_id: facility.id,
            name: clinic[:service_name],
            facility_name: facility.name,
            address: parse_lighthouse_address(facility.address),
            phone: facility.phone&.dig('healthConnect') || facility.phone&.dig('health_connect'),
            latitude: facility.lat,
            longitude: facility.long,
            facility_type: facility.facility_type,
            service_type:
          )
        end

        def self.parse_lighthouse_address(address_hash)
          return nil if address_hash.blank?

          physical = address_hash['physical'] || address_hash[:physical]
          return nil if physical.blank?

          {
            street1: physical['address1'] || physical['address_1'],
            street2: physical['address2'] || physical['address_2'],
            street3: physical['address3'] || physical['address_3'],
            city: physical['city'],
            state: physical['state'],
            zip: physical['zip']
          }
        end
      end
    end
  end
end
