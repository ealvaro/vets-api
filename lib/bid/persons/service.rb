# frozen_string_literal: true

require 'bid/persons/configuration'
require 'bid/service'
require 'common/client/base'

# module for BID service
# See https://bip-vetservices-person-dev.dev.bip.va.gov/swagger-ui.html#/
module BID
  # Persons module containing configuration and service classes for BID Persons API
  module Persons
    # Service class for interacting with BID Persons API
    class Service < BID::Service
      configuration BID::Persons::Configuration

      # StatsD key prefix for metrics tracking
      STATSD_KEY_PREFIX = 'api.bid.persons'

      # Retrieves relationships information for current user
      # @return [Faraday::Response] the HTTP response containing relationships data
      def get_relationships(participant_id)
        with_monitoring do
          perform(
            :get,
            "#{config.base_path}relationships/#{participant_id}",
            nil,
            request_headers
          )
        end
      end

      private

      # Constructs the request headers for API calls
      # @return [Hash] headers hash including authorization token
      def request_headers
        {
          Authorization: "Bearer #{BID::Persons::JwtGenerator.encode_jwt}"
        }
      end
    end
  end
end
