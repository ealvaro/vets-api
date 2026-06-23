# frozen_string_literal: true

require 'bid/configuration'
require 'bid/persons/jwt_generator'

# module for BID service
module BID
  # Persons module containing configuration and service classes for BID Persons API
  module Persons
    # Configuration class for BID Persons service
    # Extends the base BID::Configuration with persons-specific settings
    class Configuration < BID::Configuration
      # Returns the base path for the BID Persons API
      # @return [String] the base URL path for persons API endpoints
      def base_path
        "#{Settings.bid.persons.base_url}/api/v1/"
      end

      # Returns the service name for logging and monitoring
      # @return [String] the service name identifier
      def service_name
        'BID/Persons'
      end

      # Checks if mock mode is enabled for the BID Persons service
      # @return [Boolean] true if mocking is enabled, false otherwise
      def mock_enabled?
        [true, 'true', 'True'].include?(Settings.bid.persons.mock)
      end
    end
  end
end
