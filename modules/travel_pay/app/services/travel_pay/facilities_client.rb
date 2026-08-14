# frozen_string_literal: true

require 'securerandom'
require_relative './base_client'

module TravelPay
  class FacilitiesClient < TravelPay::BaseClient
    def initialize(auth_session)
      super()
      @auth_session = auth_session
    end

    ##
    # HTTP GET call to the BTSSS 'facilities/{facility_id}/related' endpoint
    # Returns facilities related to the given home facility, supporting pagination and filtering.
    #
    # @param facility_id [String] UUID of the home facility
    # @param params [Hash] optional query params: page_number, page_size, sort_field, sort_direction,
    #                      station_number, name
    # @return [Faraday::Response]
    #
    def get_related_facilities(facility_id, params = {})
      correlation_id = SecureRandom.uuid
      monitor.log(:info, 'Correlation ID', correlation_id:)
      url_params = params.transform_keys { |k| k.to_s.camelize(:lower) }

      log_to_statsd('facilities', 'get_related') do
        connection(server_url: btsss_url).get("api/v3/facilities/#{facility_id}/related", url_params) do |req|
          req.headers.merge!(
            'Authorization' => "Bearer #{@auth_session.veis_token}",
            'BTSSS-Access-Token' => @auth_session.btsss_token,
            'X-Correlation-ID' => correlation_id,
            **claim_headers
          )
        end
      end
    end

    private

    def btsss_url
      Settings.travel_pay.base_url
    end
  end
end
