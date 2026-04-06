# frozen_string_literal: true

module VAOS
  module V2
    module Unified
      class VASlot < BaseSlot
        attr_accessor :location_id, :clinic_ien

        def initialize(attrs = {})
          super
          self.provider_type = 'va'
        end

        # Builds a VASlot from a VAOS slot response (OpenStruct or Hash).
        # VA slots carry an opaque encoded ID plus embedded location/clinic context.
        def self.from_vaos_slot(slot, location_id: nil)
          slot = slot.to_h if slot.is_a?(OpenStruct)

          clinic_ien_value = slot.dig(:clinic, :clinic_ien)
          location_id_value = location_id || slot.dig(:location, :vha_facility_id)

          new(
            id: slot[:id],
            start: slot[:start],
            end: slot[:end],
            provider_id: clinic_ien_value,
            location_id: location_id_value,
            clinic_ien: clinic_ien_value
          )
        end
      end
    end
  end
end
