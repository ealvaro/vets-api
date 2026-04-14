# frozen_string_literal: true

module VAOS
  module V2
    module Unified
      ##
      # Books EPS (community care) appointments via {Eps::AppointmentService} draft-then-submit.
      #
      # Redis caching and {Eps::AppointmentStatusJob} enqueue run inside
      # {Eps::AppointmentService#submit_appointment} (+persist_submit_side_effects+); this class does not
      # duplicate that behavior.
      #
      class EpsBookingService < BaseBookingService
        ##
        # @param appointment_service [Eps::AppointmentService, nil] optional injection for tests;
        #   defaults to a new service built from the +user+ passed to {#book}.
        #
        def initialize(appointment_service: nil)
          super()
          @appointment_service = appointment_service
        end

        private

        def perform_booking(user:, provider:, slot:, params:)
          validate_provider!(provider)
          raise BookingArgumentError, 'slot is required' if slot.nil?

          p = params.with_indifferent_access
          referral_number = resolve_referral_number(p)
          eps = appointment_service_for(user)
          draft_id = resolve_draft_id(p, eps, referral_number)

          submit_params = build_submit_params(provider:, slot:, params: p, referral_number:)
          result = eps.submit_appointment(draft_id, submit_params)

          build_booking_confirmation(
            appointment_id: extract_appointment_id(result),
            provider_type: provider.provider_type,
            status: extract_status(result),
            start: extract_confirmation_start(result, slot)
          )
        end

        def appointment_service_for(user)
          @appointment_service || Eps::AppointmentService.new(user)
        end

        def validate_provider!(provider)
          return if provider.is_a?(VAOS::V2::Unified::EpsProvider)

          raise BookingArgumentError, "EpsBookingService requires an EpsProvider, got #{provider.class.name}"
        end

        def resolve_draft_id(params, eps, referral_number)
          existing = params[:appointment_id].presence
          return existing if existing

          draft = eps.create_draft_appointment(referral_id: referral_number)
          extract_draft_appointment_id(draft)
        end

        def resolve_referral_number(params)
          ref = params[:referral_number].presence || params[:referral_id].presence
          raise BookingArgumentError, 'referral_number or referral_id is required for EPS booking' if ref.blank?

          ref.to_s
        end

        def build_submit_params(provider:, slot:, params:, referral_number:)
          network_id = params[:network_id].presence || provider.network_id
          provider_service_id = params[:provider_service_id].presence || provider.provider_service_id
          provider_service_id ||= slot.provider_service_id
          slot_id = resolve_slot_id(slot, params)

          raise BookingArgumentError, 'network_id is required (params or EpsProvider)' if network_id.blank?

          if provider_service_id.blank?
            raise BookingArgumentError,
                  'provider_service_id is required (params, EpsProvider, or EpsSlot)'
          end

          submit = {
            network_id: network_id.to_s,
            provider_service_id: provider_service_id.to_s,
            slot_ids: [slot_id.to_s],
            referral_number: referral_number.to_s
          }

          if params[:additional_patient_attributes].present?
            submit[:additional_patient_attributes] = params[:additional_patient_attributes]
          end

          submit
        end

        def resolve_slot_id(slot, params)
          sid = params[:slot_id].presence || slot.id.presence
          raise BookingArgumentError, 'slot id is required (params[:slot_id] or slot.id)' if sid.blank?

          sid
        end

        def extract_draft_appointment_id(draft)
          id = draft.id
          raise BookingUpstreamContractError, 'EPS draft response missing appointment id' if id.blank?

          id
        end

        def extract_appointment_id(result)
          id = result.id
          raise BookingUpstreamContractError, 'EPS submit response missing appointment id' if id.blank?

          id
        end

        def extract_status(result)
          result.state.presence || 'booked'
        end

        def extract_confirmation_start(result, slot)
          result.start || result.local_start_time || slot.start
        end
      end
    end
  end
end
