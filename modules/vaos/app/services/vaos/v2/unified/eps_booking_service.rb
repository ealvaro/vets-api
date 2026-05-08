# frozen_string_literal: true

module VAOS
  module V2
    module Unified
      ##
      # Books EPS (community care) appointments via {Eps::AppointmentService} draft-then-submit.
      #
      # Redis caching of post-submit status data and {Eps::AppointmentStatusJob} enqueue
      # run inside {Eps::AppointmentService#submit_appointment} (+persist_submit_side_effects+);
      # this class does not duplicate that behavior.
      #
      # The pre-submit draft id is resolved from a separate +(user, referral_number)+
      # Redis cache populated by {VAOS::V2::UnifiedSlotsController#maybe_create_draft}.
      # Cache hit reuses the slots-time draft and avoids an orphan; cache miss
      # falls back through {EpsDraftService} so the referral-used guard still
      # runs before minting a fresh draft.
      #
      class EpsBookingService < BaseBookingService
        ##
        # @param appointment_service [Eps::AppointmentService, nil] optional injection for tests;
        #   defaults to a new service built from the +user+ passed to {#book}.
        # @param redis_client [Eps::RedisClient, nil] optional injection for tests;
        #   defaults to a new client. Used to resolve and invalidate the cached draft id.
        # @param eps_draft_service [VAOS::V2::Unified::EpsDraftService, nil] optional
        #   injection for tests; defaults to a new service built from the +user+ passed to {#book}.
        #
        def initialize(appointment_service: nil, redis_client: nil, eps_draft_service: nil)
          super()
          @appointment_service = appointment_service
          @redis_client = redis_client
          @eps_draft_service = eps_draft_service
        end

        private

        def perform_booking(user:, provider:, slot:, params:)
          validate_provider!(provider)
          raise BookingArgumentError, 'slot is required' if slot.nil?

          p = params.with_indifferent_access
          referral_number = resolve_referral_number(p)
          appointment_service = appointment_service_for(user)
          draft_id = resolve_draft_id(user:, referral_number:)

          submit_params = build_submit_params(provider:, slot:, params: p, referral_number:)
          result = appointment_service.submit_appointment(draft_id, submit_params)

          # Drop the cached draft id once the submit has succeeded so a retry
          # cannot reuse a Wellhive draft that's already been consumed.
          invalidate_cached_draft_id(user:, referral_number:)

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

        def redis_client
          @redis_client ||= Eps::RedisClient.new
        end

        def eps_draft_service_for(user)
          @eps_draft_service ||= EpsDraftService.new(user)
        end

        def validate_provider!(provider)
          return if provider.is_a?(VAOS::V2::Unified::EpsProvider)

          raise BookingArgumentError, "EpsBookingService requires an EpsProvider, got #{provider.class.name}"
        end

        # The submit endpoint (+POST /appointments/{appointment_id}/submit+) requires
        # a Wellhive draft id, NOT a +provider_service_id+. Resolution order:
        #
        # 1. Look up a draft cached by {VAOS::V2::UnifiedSlotsController#maybe_create_draft}
        #    under +(user.uuid, referral_number)+. Hit reuses the slots-time draft.
        # 2. Cache miss (Redis unavailable, TTL expired, slots step skipped): use
        #    {EpsDraftService#create_for_referral} to re-run the referral-used guard
        #    and mint a resumable draft. The slot id chosen by the FE is already
        #    (network, provider, time, appointment-type)-scoped, not draft-scoped, so
        #    it remains valid against a freshly-minted draft.
        #
        # Earlier versions accepted +params[:appointment_id]+ from the client; that
        # shortcut produced a class of +400 invalid appointmentId+ failures whenever
        # the FE populated the field with the +provider_service_id+ instead of the
        # draft id. Client-supplied draft ids are no longer trusted at any layer.
        def resolve_draft_id(user:, referral_number:)
          cached = fetch_cached_draft_id(user:, referral_number:)
          return cached if cached.present?

          eps_draft_service_for(user).create_for_referral(
            OpenStruct.new(referral_number:)
          )
        end

        def fetch_cached_draft_id(user:, referral_number:)
          redis_client.fetch_draft_appointment_id(uuid: user&.uuid, referral_number:)
        end

        def invalidate_cached_draft_id(user:, referral_number:)
          redis_client.delete_draft_appointment_id(uuid: user&.uuid, referral_number:)
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
