# frozen_string_literal: true

require 'bid/configuration'
require 'bid/claims/jwt_generator'

# module for BID service
module BID
  # Claims module containing configuration and service classes for BID Claims functionality
  module Claims
    # Configuration class for BID Claims service
    # Extends the base BID::Configuration with claims-specific settings
    class Configuration < BID::Configuration
      # Returns the base path for the BID Claims API
      # @return [String] the base URL path for claims API endpoints
      def base_path
        "#{Settings.bid.claims.base_url}/api/v1/"
      end

      # Returns the service name for logging and monitoring
      # @return [String] the service name identifier
      def service_name
        'BID/Claims'
      end

      # Checks if mock mode is enabled for the BID Claims service
      # @return [Boolean] true if mocking is enabled, false otherwise
      def mock_enabled?
        [true, 'true', 'True'].include?(Settings.bid.claims.mock)
      end
    end
  end
end
