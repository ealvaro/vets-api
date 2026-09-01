# frozen_string_literal: true

require 'vets/model'

module FacilitiesApi
  module V2
    module Lighthouse
      class NearbyResponse
        include Vets::Model

        # There is no pagination on the /nearby response. The payload's +meta+ is
        # intentionally dropped: its only member is +bandVersion+ (the vintage of
        # Lighthouse's precomputed drive-time bands), which no consumer reads -- drive-time
        # enrichment needs the per-facility bands, not their version. Surface it here if a
        # consumer ever needs to reason about band staleness.
        attribute :body, String
        attribute :data, Hash, array: true
        attribute :status, Integer

        def initialize(body, status)
          super()
          @body = body
          @status = status
          @data = Array.wrap(JSON.parse(body)['data']) # normalize data to array
        end

        def nearby_facilities
          data.map { |facility| V2::Lighthouse::NearbyFacility.new(facility) }
        end
      end
    end
  end
end
