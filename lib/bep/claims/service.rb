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

      def initialize
        super(nil)
      end

      # Retrieves pension claims information for the current user
      # @return [Faraday::Response] the HTTP response containing pension award data
      def create_claim(params)
        with_monitoring do
          perform(
            :post,
            "#{config.base_path}claims",
            params.to_json,
            request_headers
          )
        end
      end

      def create_contentions(claim_id, params)
        with_monitoring do
          perform(
            :post,
            "#{config.base_path}claims/#{claim_id}/contentions",
            params.to_json,
            request_headers
          )
        end
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
