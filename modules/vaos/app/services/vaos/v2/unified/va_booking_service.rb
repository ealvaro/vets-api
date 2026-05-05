# frozen_string_literal: true

module VAOS
  module V2
    module Unified
      ##
      # Books VA in-person (clinic) direct-scheduled appointments via
      # {VAOS::V2::AppointmentsService#post_appointment}, mapping {VAProvider} and slot data into the
      # request shape expected by {VAOS::V2::AppointmentForm}.
      #
      class VABookingService < BaseBookingService
        PILOT_REASON_CODE = { text: 'comments:Scheduled via unified scheduling pilot' }.freeze

        private

        def perform_booking(user:, provider:, slot:, params:)
          validate_provider!(provider)
          request_body = build_post_appointment_request(provider:, slot:, params:)
          result = appointments_service_for(user).post_appointment(request_body)
          build_booking_confirmation(
            appointment_id: extract_appointment_id(result),
            provider_type: provider.provider_type,
            status: extract_status(result),
            start: extract_confirmation_start(result)
          )
        end

        def appointments_service_for(user)
          VAOS::V2::AppointmentsService.new(user)
        end

        def validate_provider!(provider)
          return if provider.is_a?(VAOS::V2::Unified::VAProvider)

          raise BookingArgumentError, "VABookingService requires a VAProvider, got #{provider.class.name}"
        end

        def build_post_appointment_request(provider:, slot:, params:)
          p = params.with_indifferent_access

          body = {
            kind: 'clinic',
            status: 'booked',
            location_id: resolve_location_id(provider),
            clinic: resolve_clinic(provider),
            slot: build_slot_payload(slot),
            reason_code: PILOT_REASON_CODE,
            system_type: 'vista',
            service_type: resolve_service_type(provider)
          }

          extension = resolve_extension(p, slot)
          body[:extension] = extension if extension.present?
          body[:comment] = p[:comment] if p[:comment].present?
          body.deep_symbolize_keys
        end

        def resolve_location_id(provider)
          raise BookingArgumentError, 'location_id is required on VAProvider' if provider.location_id.blank?

          provider.location_id.to_s
        end

        def resolve_clinic(provider)
          raise BookingArgumentError, 'provider id (clinic) is required for VA direct scheduling' if provider.id.blank?

          provider.id.to_s
        end

        def resolve_service_type(provider)
          raise BookingArgumentError, 'service_type is required on VAProvider' if provider.service_type.blank?

          provider.service_type.to_s
        end

        def build_slot_payload(slot)
          raise BookingArgumentError, 'slot is required' if slot.nil?
          raise BookingArgumentError, 'slot id is required for VA booking' if slot.id.blank?

          { id: slot.id.to_s }
        end

        def resolve_extension(params, slot)
          ext = params[:extension]
          return ext if ext.present?

          return nil if slot.start.blank?

          desired_date = parse_slot_start_for_extension(slot)
          return nil if desired_date.nil?

          { desired_date: }
        end

        ##
        # Returns +nil+ when +slot.start+ is non-blank but +Time.zone.parse+ returns +nil+ for
        # totally unrecognized input (e.g. "not-a-date") so the caller can omit the +desired_date+
        # extension instead of raising +NoMethodError+. The other failure mode of +Time.zone.parse+
        # is raising +ArgumentError+ for partly-valid but out-of-range input (e.g. "2026-13-99");
        # that is logged and re-raised so the error surfaces back to the controller rather than
        # being silently dropped. +desired_date+ is a VistA-reporting field on the appointment.
        def parse_slot_start_for_extension(slot)
          parsed = Time.zone.parse(slot.start.to_s)
          return parsed.to_datetime if parsed

          log_unparseable_slot_start(slot.start)
          nil
        rescue ArgumentError => e
          log_unparseable_slot_start(slot.start, error: e.message)
          raise
        end

        def log_unparseable_slot_start(slot_start, error: nil)
          Rails.logger.warn(
            'VABookingService: unparseable slot.start, omitting desired_date',
            { slot_start:, error: }.compact
          )
        end

        def extract_appointment_id(result)
          raise BookingUpstreamContractError, 'VA booking response missing appointment id' if result.id.blank?

          result.id
        end

        def extract_status(result)
          result.status.presence || 'booked'
        end

        def extract_confirmation_start(result)
          result.start
        end
      end
    end
  end
end
