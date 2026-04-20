# frozen_string_literal: true

module VAOS
  module V2
    module Unified
      class EpsSlot < BaseSlot
        DURATION_SEGMENT_PATTERN = /\A(?:(?<hours>\d+)h)?(?:(?<minutes>\d+)m)?(?:(?<seconds>\d+)s)?\z/

        def initialize(attrs = {})
          super
          self.provider_type = 'eps'
        end

        # Builds an EpsSlot from an EPS slot response (Hash).
        # EPS slots carry an opaque composite ID and a providerServiceId.
        # EPS slots may not include an explicit end time; when missing, we derive it from the
        # duration segment in the slot ID when possible, otherwise it is left nil.
        def self.from_eps_slot(slot)
          slot = slot.to_h if slot.is_a?(OpenStruct)

          new(
            id: slot[:id],
            start: slot[:start],
            end: normalized_end_time(slot),
            provider_id: slot[:provider_service_id],
            provider_service_id: slot[:provider_service_id]
          )
        end

        def self.normalized_end_time(slot)
          return slot[:end] if slot[:end].present?

          duration = duration_from_slot_id(slot[:id])
          return nil if slot[:start].blank? || duration.nil?

          start_time = Time.zone.parse(slot[:start].to_s)
          return nil if start_time.nil?

          (start_time.utc + duration).iso8601
        end

        def self.duration_from_slot_id(slot_id)
          duration_segment = slot_id.to_s.split('|')[3]
          return nil if duration_segment.blank?

          match = DURATION_SEGMENT_PATTERN.match(duration_segment)
          return nil unless match

          match[:hours].to_i.hours + match[:minutes].to_i.minutes + match[:seconds].to_i.seconds
        end
      end
    end
  end
end
