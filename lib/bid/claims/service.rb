# frozen_string_literal: true

require 'bid/claims/configuration'
require 'bid/service'
require 'common/client/base'

# module for BID service
module BID
  # Claims module containing configuration and service classes for BID Claims functionality
  module Claims
    # Service class for interacting with BID Claims API
    class Service < BID::Service
      configuration BID::Claims::Configuration

      # StatsD key prefix for metrics tracking
      STATSD_KEY_PREFIX = 'api.bid.claims'

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

      def create_contention(claim_id, params)
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
          Authorization: "Bearer #{BID::Claims::JwtGenerator.encode_jwt}",
          'Content-Type': 'application/json'
        }
      end
    end
  end
end
