# frozen_string_literal: true

module VAOS
  module V2
    module Unified
      class ProviderSlotsSerializer
        def initialize(provider:, slots:, draft_appointment_id:)
          @provider = provider
          @slots = slots
          @draft_appointment_id = draft_appointment_id
        end

        def serialize
          {
            data: {
              id: @provider.id,
              type: 'provider_slots',
              attributes: {
                provider: serialize_provider,
                slots: @slots.map { |s| serialize_slot(s) },
                draftAppointmentId: @draft_appointment_id
              }.compact
            }
          }
        end

        private

        def serialize_provider
          VAOS::V2::UnifiedProviderSerializer.new.serialize([@provider]).first
        end

        def serialize_slot(slot)
          {
            id: slot.id,
            start: slot.start,
            end: slot.end,
            providerServiceId: slot.provider_service_id,
            providerType: slot.provider_type
          }.compact
        end
      end
    end
  end
end
