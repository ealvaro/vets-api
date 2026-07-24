# frozen_string_literal: true

require 'bep/awards/configuration'
require 'bep/service'
require 'common/client/base'

# module for BEP service
module BEP
  # Awards module containing configuration and service classes for BEP Awards functionality
  module Awards
    # Service class for interacting with BEP Awards API
    # Handles pension award data retrieval for veterans
    class Service < BEP::Service
      configuration BEP::Awards::Configuration

      # StatsD key prefix for metrics tracking
      STATSD_KEY_PREFIX = 'api.bep.awards'

      # Retrieves pension awards information for the current user
      # @return [Faraday::Response] the HTTP response containing pension award data
      def get_awards_pension(participant_id)
        with_monitoring do
          perform(
            :get,
            "#{config.base_path}pension/#{participant_id}",
            nil,
            request_headers
          )
        end
      end

      # This method will retrieve a list of current award events for the user
      # Mock response is defined in: spec/lib/bep/awards/support/current_awards_response.rb (RSpec shared context)
      def get_current_awards(participant_id)
        with_monitoring do
          perform(
            :get,
            "#{config.base_path}current/#{participant_id}/beneficiaryId/#{participant_id}?awardTC=CPL",
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
          Authorization: "Bearer #{BEP::Awards::JwtGenerator.encode_jwt}"
        }
      end
    end
  end
end
