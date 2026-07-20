# frozen_string_literal: true

require 'bep/configuration'
require 'bep/claims/jwt_generator'

# module for BEP service
module BEP
  # Claims module containing configuration and service classes for BEP Claims functionality
  module Claims
    # Configuration class for BEP Claims service
    # Extends the base BEP::Configuration with claims-specific settings
    class Configuration < BEP::Configuration
      # Returns the base path for the BEP Claims API
      # @return [String] the base URL path for claims API endpoints
      def base_path
        "#{Settings.bep.claims.base_url}/api/v1/"
      end

      # Returns the service name for logging and monitoring
      # @return [String] the service name identifier
      def service_name
        'BEP/Claims'
      end

      # Checks if mock mode is enabled for the BEP Claims service
      # @return [Boolean] true if mocking is enabled, false otherwise
      def mock_enabled?
        [true, 'true', 'True'].include?(Settings.bep.claims.mock)
      end
    end
  end
end
