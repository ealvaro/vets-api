# frozen_string_literal: true

require 'common/client/base'
require_relative 'nearby_configuration'
require_relative 'nearby_response'

module FacilitiesApi
  module V2
    module Lighthouse
      # Client for the VA Facilities "nearby" endpoint. Separate from
      # {FacilitiesApi::V2::Lighthouse::Client} only so it can carry its own breaker
      # (see {NearbyConfiguration}); the request/response handling is otherwise the same.
      #
      # Documentation located at:
      # https://developer.va.gov/explore/api/va-facilities/docs
      class NearbyClient < Common::Client::Base
        configuration V2::Lighthouse::NearbyConfiguration

        ##
        # Request a list of nearby facilities and their calculated drive-time bands
        # * Returns only health facilities
        # * Returns only facilities within a 90-minute drive time
        # @param params [Hash] must include full address or lat and long
        #   see https://developer.va.gov/explore/api/va-facilities/docs for more options
        # @example  client.nearby(lat: 40.7128, long: -74.006)
        # @return [Array<V2::Lighthouse::NearbyFacility>]
        #
        def nearby(params)
          response = perform(:get, '/services/va_facilities/v1/nearby', params)
          V2::Lighthouse::NearbyResponse.new(response.body, response.status).nearby_facilities
        end
      end
    end
  end
end
