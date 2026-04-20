# frozen_string_literal: true

module VAOS
  module V2
    module Unified
      class AppointmentSerializer
        include VAOS::FacilityConstants

        # Both VA and CC appointments are normalized to the same response shape so the
        # frontend receives a single contract regardless of provider_type.
        # VA appointments come from VAOS::V2::AppointmentsService (OpenStruct with facility data);
        # CC appointments come from Eps::AppointmentService via the EpsAppointment model.
        def initialize(appointment, care_type:)
          @appointment = appointment
          @care_type = care_type
        end

        def serialize
          {
            data: {
              id: @appointment.id,
              type: 'appointment',
              attributes: build_attributes.compact
            }
          }
        end

        private

        def build_attributes
          case @care_type
          when 'VA'
            build_va_attributes
          when 'CC'
            build_cc_attributes
          end
        end

        def build_va_attributes
          attrs = {
            id: @appointment.id,
            status: @appointment.status,
            careType: 'VA',
            start: @appointment.start,
            past: @appointment.past,
            modality: @appointment.modality,
            provider: build_va_provider
          }
          attrs[:facilityError] = FACILITY_ERROR_MSG if facility_error?
          attrs
        end

        def build_cc_attributes
          {
            id: @appointment.id,
            status: @appointment.status,
            careType: 'CC',
            start: @appointment.start,
            isLatest: @appointment.is_latest,
            lastRetrieved: @appointment.last_retrieved,
            referralId: @appointment.referral_id,
            past: @appointment.past,
            modality: 'communityCareUnified',
            provider: @appointment.provider_details,
            location: @appointment.location
          }
        end

        # VA appointments don't have an individual provider like CC does.
        # Instead, the "provider" maps to the facility (practice) + clinic (name)
        # so the frontend can display consistent provider-like info for both care types.
        def build_va_provider
          facility = va_facility
          return nil if facility.nil?

          {
            name: @appointment.service_name || fval(facility, 'name'),
            practice: fval(facility, 'name'),
            phone: facility_main_phone(facility),
            location: build_va_provider_location(facility)
          }.compact
        end

        def build_va_provider_location(facility)
          {
            name: fval(facility, 'name'),
            address: format_va_address(facility),
            latitude: fval(facility, 'lat'),
            longitude: fval(facility, 'long'),
            timezone: facility_timezone_id(facility)
          }.compact
        end

        def format_va_address(facility)
          address = fval(facility, 'physicalAddress') || fval(facility, 'physical_address')
          return nil if address.blank?

          line = fval(address, 'line')
          city = fval(address, 'city')
          state = fval(address, 'state')
          postal = fval(address, 'postalCode') || fval(address, 'postal_code')

          [line&.join(', '), city, state, postal].compact.join(', ')
        end

        def facility_main_phone(facility)
          phone = fval(facility, 'phone')
          return nil if phone.blank?

          fval(phone, 'main')
        end

        def facility_timezone_id(facility)
          tz = fval(facility, 'timezone')
          return nil if tz.blank?

          fval(tz, 'zoneId') || fval(tz, 'zone_id')
        end

        # Returns the facility hash for VA appointments, or nil if the location
        # is missing or set to the error string by set_facility_error_msg.
        def va_facility
          loc = @appointment.location
          loc.is_a?(Hash) ? loc : nil
        end

        # True when set_facility_error_msg replaced the location with the error
        # sentinel, meaning a location_id existed but facility lookup failed.
        def facility_error?
          @appointment.location == FACILITY_ERROR_MSG
        end

        # Facility data may arrive with string or symbol keys depending on the
        # upstream middleware. This helper checks both.
        def fval(hash, key)
          hash[key] || hash[key.to_sym]
        end
      end
    end
  end
end
