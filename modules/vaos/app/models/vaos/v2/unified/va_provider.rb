# frozen_string_literal: true

module VAOS
  module V2
    module Unified
      # Represents a single VA schedulable clinic (clinic IEN) at a Lighthouse facility.
      # +id+ is the clinic IEN. +location_id+ is the parent facility +unique_id+ used with VAOS
      # clinics and slots APIs.
      class VAProvider < BaseProvider
        attr_accessor :location_id, :facility_type

        def initialize(attrs = {})
          super
          self.provider_type = 'va'
        end

        ##
        # @param facility [FacilitiesApi::V2::Lighthouse::Facility] parent facility (address, geo, phone)
        # @param clinic [OpenStruct, Hash] VAOS clinic payload from SystemsService#get_facility_clinics
        #
        def self.from_facility_and_clinic(facility, clinic)
          clinic = clinic.to_h if clinic.is_a?(OpenStruct)

          new(
            id: clinic[:id],
            location_id: facility.unique_id,
            name: clinic[:service_name],
            facility_name: facility.name,
            address: parse_lighthouse_address(facility.address),
            phone: facility.phone&.dig('main'),
            latitude: facility.lat,
            longitude: facility.long,
            facility_type: facility.facility_type
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
