# frozen_string_literal: true

require 'common/client/configuration/rest'
require 'vha_notification/constants'

module VHANotification
  class Configuration < Common::Client::Configuration::REST
    VHA_CONSENT_ENDPOINT = '/api/v1/cfapivhanotificationapi/vha-consent-and-enrollment'

    timeout_value = Settings.vha_notification&.timeout.to_i
    self.read_timeout = timeout_value.positive? ? timeout_value : 30

    ##
    # @return [Config::Options] Settings for VHA notification API
    #
    def settings
      Settings.vha_notification
    end

    def service_name
      'VHANotification'
    end

    def base_path
      Settings.vha_notification.base_url
    end

    ##
    # Updates VHA and enrollment information
    #
    # @param [String] pid - Veteran's PID
    # @param [Hash] payload - Consent data
    # @param [String] bearer_token - Bearer token for authorization
    # @return [Faraday::Response] Response from the VHA API
    #
    def post_consent_update(pid, payload, bearer_token)
      headers = base_request_headers.merge(
        'Authorization' => "Bearer #{bearer_token}",
        'Content-Type' => 'application/json'
      )

      connection.put(
        "#{VHA_CONSENT_ENDPOINT}/#{pid}",
        payload.to_json,
        headers
      )
    rescue => e
      log_consent_error(e)
      raise
    end

    ##
    # Creates a Faraday connection with JSON parsing and breakers functionality
    #
    # @return [Faraday::Connection] A Faraday connection instance
    #
    def connection
      @conn ||= Faraday.new(base_path, headers: base_request_headers, request: request_options) do |faraday|
        faraday.use(:breakers, service_name:)
        faraday.use Faraday::Response::RaiseError

        faraday.request :json
        faraday.response :json
        faraday.adapter Faraday.default_adapter
      end
    end

    private

    def log_consent_error(error)
      ::Rails.logger.error(
        "VHA Notification API Consent Update Error: #{error.message}",
        { error_class: error.class.to_s, service: service_name }
      )
    end
  end
end
