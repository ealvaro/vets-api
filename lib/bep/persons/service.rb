# frozen_string_literal: true

require 'bep/persons/configuration'
require 'bep/service'
require 'common/client/base'

# module for BEP service
# See https://bip-vetservices-person-dev.dev.bip.va.gov/swagger-ui.html#/
module BEP
  # Persons module containing configuration and service classes for BEP Persons API
  module Persons
    # Service class for interacting with BEP Persons API
    class Service < BEP::Service
      configuration BEP::Persons::Configuration

      # StatsD key prefix for metrics tracking
      STATSD_KEY_PREFIX = 'api.bep.persons'

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
          Authorization: "Bearer #{BEP::Persons::JwtGenerator.encode_jwt}"
        }
      end
    end
  end
end
