# frozen_string_literal: true

require 'bep/claims/configuration'
require 'bep/service'
require 'common/client/base'

# module for BEP service
module BEP
  # Claims module containing configuration and service classes for BEP Claims functionality
  module Claims
    # Service class for interacting with BEP Claims API
    class Service < BEP::Service
      configuration BEP::Claims::Configuration

      # StatsD key prefix for metrics tracking
      STATSD_KEY_PREFIX = 'api.bep.claims'

      # Retrieves pension claims information for the current user
      # @return [Faraday::Response] the HTTP response containing pension award data
      def create_claim(params)
        perform_with_monitoring(
          method: :post,
          path: "#{config.base_path}claims",
          params: params.to_json,
          headers: request_headers,
          endpoint_name: 'create_claim'
        )
      end

      def create_contentions(claim_id, params)
        perform_with_monitoring(
          method: :post,
          path: "#{config.base_path}claims/#{claim_id}/contentions",
          params: params.to_json,
          headers: request_headers,
          endpoint_name: 'create_contentions'
        )
      end

      protected

      def monitor
        @monitor ||= Monitor.new('bep-claims-api', metric_prefix: 'api.bep.claims')
      end

      private

      # Constructs the request headers for API calls
      # @return [Hash] headers hash including authorization token
      def request_headers
        {
          Authorization: "Bearer #{BEP::Claims::JwtGenerator.encode_jwt}",
          'Content-Type': 'application/json'
        }
      end
    end
  end
end
