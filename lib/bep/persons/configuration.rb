# frozen_string_literal: true

require 'bep/configuration'
require 'bep/persons/jwt_generator'

# module for BEP service
module BEP
  # Persons module containing configuration and service classes for BEP Persons API
  module Persons
    # Configuration class for BEP Persons service
    # Extends the base BEP::Configuration with persons-specific settings
    class Configuration < BEP::Configuration
      # Returns the base path for the BEP Persons API
      # @return [String] the base URL path for persons API endpoints
      def base_path
        "#{Settings.bep.persons.base_url}/api/v1/"
      end

      # Returns the service name for logging and monitoring
      # @return [String] the service name identifier
      def service_name
        'BEP/Persons'
      end

      # Checks if mock mode is enabled for the BEP Persons service
      # @return [Boolean] true if mocking is enabled, false otherwise
      def mock_enabled?
        [true, 'true', 'True'].include?(Settings.bep.persons.mock)
      end
    end
  end
end
