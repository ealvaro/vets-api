# frozen_string_literal: true

require 'bep/configuration'
require 'bep/awards/jwt_generator'

# module for BEP service
module BEP
  # Awards module containing configuration and service classes for BEP Awards functionality
  module Awards
    # Configuration class for BEP Awards service
    # Extends the base BEP::Configuration with awards-specific settings
    class Configuration < BEP::Configuration
      # Returns the base path for the BEP Awards API
      # @return [String] the base URL path for awards API endpoints
      def base_path
        "#{Settings.bep.awards.base_url}/api/v1/awards/"
      end

      # Returns the service name for logging and monitoring
      # @return [String] the service name identifier
      def service_name
        'BEP/Awards'
      end

      # Checks if mock mode is enabled for the BEP Awards service
      # @return [Boolean] true if mocking is enabled, false otherwise
      def mock_enabled?
        Settings.bep.awards.mock || false
      end
    end
  end
end
