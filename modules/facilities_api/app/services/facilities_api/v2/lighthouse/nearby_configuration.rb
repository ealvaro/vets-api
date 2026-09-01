# frozen_string_literal: true

require_relative 'configuration'

module FacilitiesApi
  module V2
    module Lighthouse
      # Faraday stack for the VA Facilities +/nearby+ endpoint. Identical to
      # {FacilitiesApi::V2::Lighthouse::Configuration} except for its breaker identity:
      # +/nearby+ gets its own +service_name+ so a nearby outage opens only its own
      # circuit. Sharing the parent's 'Lighthouse_Facilities' breaker would let a
      # nearby outage cut off +/facilities+ too -- the call that produces the VA
      # provider list -- turning drive-time enrichment's fail-open ("providers with
      # blank drive times") into "no VA providers at all". The distinct name also
      # separates nearby from the rest of facilities traffic in breaker logs/metrics.
      class NearbyConfiguration < Configuration
        def service_name
          'Lighthouse_Facilities_Nearby'
        end

        def instrumentation_name
          'lighthouse.facilities.v2.nearby.request.faraday'
        end
      end
    end
  end
end
