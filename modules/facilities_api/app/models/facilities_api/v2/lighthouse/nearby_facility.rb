# frozen_string_literal: true

require 'vets/model'

# Model for responses from the VA Facilities "nearby" endpoint, which only returns a
# facility ID and its drive-time band (min/max minutes) for health facilities within a
# 90-minute drive of the origin. The v1 payload uses camelCase (minTime/maxTime); the
# snake_case fallback keeps this tolerant of the v0 shape.
module FacilitiesApi
  module V2
    module Lighthouse
      class NearbyFacility
        include Vets::Model

        attribute :id, String
        attribute :min_time, Integer
        attribute :max_time, Integer

        def initialize(fac)
          super()
          self.id = fac['id']
          attrs = fac['attributes'] || {}
          self.min_time = attrs['minTime'] || attrs['min_time']
          self.max_time = attrs['maxTime'] || attrs['max_time']
        end
      end
    end
  end
end
