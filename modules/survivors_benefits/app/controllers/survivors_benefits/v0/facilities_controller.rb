# frozen_string_literal: true

module SurvivorsBenefits
  module V0
    ###
    # The Survivors Benefits facilities controller that handles facilities data
    #
    class FacilitiesController < ClaimsBaseController
      MAX_PER_PAGE = 1000
      service_tag 'survivors-benefits'

      def index
        state_filter = build_state_filter(facility_params['state'])
        cache_key = "VA_health_facilities::#{state_filter}"
        facilities = cached_facilities(cache_key, state_filter)
        render json: facilities
      end

      private

      # the constants.json file in vets-json-schema has 'PI' as the state code for the Philippines,
      # but the Facilities API expects 'PH', so we need to convert it here
      # NOTE: If this is fixed in the constants file, behavior will not break as the
      # build_state_filter method will just return the state as is.
      #
      # @param state [String] - the state code to filter by
      # @return [String] - the state code to use for the Facilities API call
      def build_state_filter(state)
        state == 'PI' ? 'PH' : state
      end

      ##
      # aggregates all facilities from the Facilities API
      # filtering by type 'health' and the state provided by the user
      #
      # @param state_filter [String] - the state to filter facilities by
      # @return [Array] - list of facilities with name, city, and state
      def cached_facilities(cache_key, state_filter)
        Rails.cache.fetch(cache_key, expires_in: 7.days) do
          client = FacilitiesApi::V2::Lighthouse::Client.new
          filters = { per_page: MAX_PER_PAGE, type: 'health', state: state_filter }
          facilities = client.get_facilities(filters).to_a
          facilities.map! do |facility|
            facility_name = facility.name
            facility_city = facility.address&.dig('physical', 'city')
            facility_state = facility.address&.dig('physical', 'state')
            if facility_name.present? && facility_city.present? && facility_state.present?
              { name: facility_name, city: facility_city, state: facility_state }
            end
          end.compact!
          facilities
        end
      end

      def facility_params
        params.permit(:state)
      end
    end
  end
end
