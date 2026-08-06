# frozen_string_literal: true

require 'securerandom'
require 'travel_pay/middleware/btsss_errors'
require 'travel_pay/middleware/btsss_logging'
require 'travel_pay/monitor'

module TravelPay
  class BaseClient
    def claim_headers
      if Settings.vsp_environment == 'production'
        {
          'Content-Type' => 'application/json',
          'Ocp-Apim-Subscription-Key-E' => Settings.travel_pay.subscription_key_e,
          'Ocp-Apim-Subscription-Key-S' => Settings.travel_pay.subscription_key_s
        }
      else
        {
          'Content-Type' => 'application/json',
          'Ocp-Apim-Subscription-Key' => Settings.travel_pay.subscription_key
        }
      end
    end

    ##
    # Create a Faraday connection object
    # @param server_url [String] The base URL for the service
    # @param multipart [Boolean] Whether to enable multipart form-data (default: false)
    # @return [Faraday::Connection]
    #
    def connection(server_url:, multipart: false)
      service_name = Settings.travel_pay.service_name

      Faraday.new(url: server_url, request: request_options) do |conn|
        conn.use(:breakers, service_name:)
        conn.response :btsss_logging if Flipper.enabled?(:travel_pay_btsss_logging)
        conn.response :raise_custom_error, error_prefix: service_name, include_request: true
        conn.response :btsss_errors if Flipper.enabled?(:travel_pay_surface_btsss_errors)
        conn.response :betamocks if mock_enabled?
        conn.response :json
        if multipart
          conn.request :multipart
          conn.request :url_encoded
        else
          conn.request :json
        end

        conn.adapter Faraday.default_adapter
      end
    end

    ##
    # Timeout options for Faraday connections
    # @return [Hash] open_timeout and timeout values
    #
    def request_options
      {
        open_timeout: Settings.travel_pay.open_timeout,
        timeout: Settings.travel_pay.timeout
      }
    end

    ##
    # Syntactic sugar for determining if the client should use
    # fake api responses or actually connect to the BTSSS API
    def mock_enabled?
      Settings.travel_pay.mock
    end

    ##
    # Helper function to measure xTIC latency
    # when calling the external Travel Pay API
    def log_to_statsd(service, tag_value, &)
      monitor.track_response_time(service, tag_value, &)
    end

    def monitor
      @monitor ||= TravelPay::Monitor.new
    end
  end
end
