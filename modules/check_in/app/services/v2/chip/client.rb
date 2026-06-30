# frozen_string_literal: true

require 'logging/helper/data_scrubber'

module V2
  module Chip
    ##
    # A service client for handling HTTP requests to the CHIP API.  This needs to be instantiated with a
    # {CheckIn::V2::Session} object so that it can be used in subsequent calls.
    #
    # @see https://va.ghe.com/software/chip CHIP readme
    #
    # @example
    #   client = Client.build(check_in_session: check_in)
    #
    # @!attribute settings
    #   @return [Config::Options]
    # @!attribute claims_token
    #   @return [V2::Chip::ClaimsToken]
    # @!attribute check_in_session
    #   @return [CheckIn::V2::Session]
    # @!method base_path
    #   @return (see Config::Options#base_path)
    # @!method tmp_api_id
    #   @return (see Config::Options#tmp_api_id)
    # @!method url
    #   @return (see Config::Options#url)
    # @!method service_name
    #   @return (see Config::Options#service_name)
    class Client
      extend Forwardable

      attr_reader :settings, :claims_token, :check_in_session

      def_delegators :settings, :service_name

      ##
      # Builds a Client instance
      #
      # @param opts [Hash] options to create a Client
      # @option opts [CheckIn::V2::Session] :check_in_session the session object
      #
      # @return [V2::Chip::Client] an instance of this class
      #
      def self.build(opts = {})
        new(opts)
      end

      def initialize(opts)
        @settings = Settings.check_in.chip_api_v2
        @claims_token = ClaimsToken.build
        @check_in_session = opts[:check_in_session]
      end

      ##
      # HTTP POST call to the CHIP API to get an access token
      #
      # @return [Faraday::Response]
      #
      def token
        connection.post("#{path_prefix}/token") do |req|
          req.headers = default_headers.merge('Authorization' => "Basic #{claims_token.static}")
        end
      end

      ##
      # HTTP POST call to the CHIP API to Check-in an appointment
      #
      # @return [Faraday::Response]
      #
      def check_in_appointment(token:, appointment_ien:, travel_params:)
        connection.post("#{path_prefix}/actions/check-in/#{check_in_session.uuid}") do |req|
          req.headers = default_headers.merge('Authorization' => "Bearer #{token}")
          req.body = { appointmentIEN: appointment_ien }.merge(travel_params).to_json
        end
      end

      ##
      # HTTP POST call to the CHIP API to refresh appointments
      #
      # @return [Faraday::Response]
      #
      def refresh_appointments(token:, identifier_params:)
        connection.post("#{path_prefix}/actions/refresh-appointments/#{check_in_session.uuid}") do |req|
          req.headers = default_headers.merge('Authorization' => "Bearer #{token}")
          req.body = identifier_params.to_json
        end
      end

      ##
      # HTTP POST call to the CHIP API to confirm pre check-in
      #
      # @return [Faraday::Response]
      #
      def pre_check_in(token:, demographic_confirmations:)
        connection.post("#{path_prefix}/actions/pre-checkin/#{check_in_session.uuid}") do |req|
          req.headers = default_headers.merge('Authorization' => "Bearer #{token}")
          req.body = demographic_confirmations.to_json
        end
      end

      ##
      # HTTP POST call to the CHIP API to set pre check-in started status. Any downstream error (non HTTP 200 response)
      # is handled by returning the original status and body.
      #
      # @return [Faraday::Response]
      #
      def set_precheckin_started(token:)
        connection.post("#{path_prefix}/actions/set-precheckin-started/#{check_in_session.uuid}") do |req|
          req.headers = default_headers.merge('Authorization' => "Bearer #{token}")
        end
      rescue => e
        Faraday::Response.new(response_body: e.original_body, status: e.original_status)
      end

      ##
      # HTTP POST call to the CHIP API to set e-check-in started status. Any downstream error (non HTTP 200 response)
      # is handled by logging and returning the original status and body.
      #
      # @return [Faraday::Response]
      #
      def set_echeckin_started(token:, appointment_attributes:)
        connection.post("#{path_prefix}/actions/set-e-check-in-started") do |req|
          req.headers = default_headers.merge('Authorization' => "Bearer #{token}")
          req.body = appointment_attributes.to_json
        end
      rescue => e
        Rails.logger.error(scrub_pii(e.message), {
          original_body: scrub_pii(e.original_body),
          original_status: e.original_status,
          uuid: check_in_session.uuid
        }.merge({ external_service: service_name, team: 'check-in' }))

        raise e
      end

      ##
      # HTTP POST call to the CHIP API to confirm demographics update
      #
      # @param token [String] CHIP token to call the endpoint
      # @param demographic_confirmations [Hash] demographic confirmations with patientDFN & stationNo
      #
      # @return [Faraday::Response]
      #
      def confirm_demographics(token:, demographic_confirmations:)
        connection.post("#{path_prefix}/actions/confirm-demographics") do |req|
          req.headers = default_headers.merge('Authorization' => "Bearer #{token}")
          req.body = demographic_confirmations.to_json
        end
      end

      ##
      # HTTP POST call to the CHIP API to refresh pre check-in data
      #
      # @param token [String] CHIP token to call the endpoint
      #
      # @return [Faraday::Response]
      #
      def refresh_precheckin(token:)
        connection.post("#{path_prefix}/actions/refresh-precheckin/#{check_in_session.uuid}") do |req|
          req.headers = default_headers.merge('Authorization' => "Bearer #{token}")
        end
      end

      ##
      # HTTP POST call to the CHIP API to initiate check-in
      #
      # @return [Faraday::Response]
      #
      def initiate_check_in(token:)
        connection.post("#{path_prefix}/actions/initiate-check-in/#{check_in_session.uuid}") do |req|
          req.headers = default_headers.merge('Authorization' => "Bearer #{token}")
        end
      end

      ##
      # HTTP DELETE call to the CHIP API to delete check-in/pre check-in data
      #
      # @param token [String] CHIP token to call the endpoint
      #
      # @return [Faraday::Response]
      #
      def delete(token:)
        connection.delete("#{path_prefix}/actions/deleteFromLorota/#{check_in_session.uuid}") do |req|
          req.headers = default_headers.merge('Authorization' => "Bearer #{token}")
        end
      rescue => e
        Rails.logger.error(scrub_pii(e.message), {
          original_body: scrub_pii(e.original_body),
          original_status: e.original_status,
          uuid: check_in_session.uuid
        }.merge({ external_service: service_name, team: 'check-in' }))

        Faraday::Response.new(response_body: e.original_body, status: e.original_status)
      end

      private

      def scrub_pii(message)
        Logging::Helper::DataScrubber.scrub(message)
      end

      ##
      # Create a Faraday connection object that glues the attributes
      # and the middleware stack for making our HTTP requests to Chip
      #
      # @return [Faraday::Connection]
      #
      def connection
        Faraday.new(url: host_url) do |conn|
          conn.use(:breakers, service_name:)
          conn.response :raise_custom_error, error_prefix: service_name
          conn.response :betamocks if mock_enabled?

          conn.adapter Faraday.default_adapter
        end
      end

      ##
      # Host portion of the configured `url` (scheme + host + non-default port),
      # stripping any path component. Used as Faraday's base URL so that
      # request paths constructed via #path_prefix don't conflict with a
      # path embedded in the `url` setting.
      #
      def host_url
        uri = URI.parse(url.to_s)
        port_part = uri.port && uri.port != uri.default_port ? ":#{uri.port}" : ''
        "#{uri.scheme}://#{uri.host}#{port_part}"
      end

      ##
      # Path prefix to prepend to CHIP endpoint paths (e.g. `/dev` before
      # `/token`). Tolerates either of two SSM-parameter shapes used across
      # CIE microservices:
      #
      #   1. `url` contains only the host, `base_path` carries the stage:
      #      url=https://host base_path=dev -> "/dev"
      #   2. `url` contains the full path (host + stage), `base_path` is
      #      ignored to avoid duplication:
      #      url=https://host/dev base_path=/dev -> "/dev"
      #
      # In either case the prefix is returned WITHOUT a trailing slash so the
      # caller can append "/token", "/actions/check-in/UUID", etc. cleanly.
      #
      def path_prefix
        url_path = URI.parse(url.to_s).path.to_s.sub(%r{/+\z}, '')
        return url_path unless url_path.empty?

        trimmed = base_path.to_s.gsub(%r{\A/+|/+\z}, '')
        trimmed.empty? ? '' : "/#{trimmed}"
      end

      ##
      # Build a hash of default headers for CHIP HTTP requests
      #
      # @return [Hash]
      #
      def default_headers
        {
          'Content-Type' => 'application/json',
          'x-apigw-api-id' => tmp_api_id
        }
      end

      def mock_enabled?
        settings.mock || Flipper.enabled?('check_in_experience_mock_enabled') || false
      end

      def use_vaec_cie_endpoints?
        Flipper.enabled?('check_in_experience_use_vaec_cie_endpoints') || false
      end

      def base_path
        use_vaec_cie_endpoints? ? settings.base_path_v2 : settings.base_path
      end

      def tmp_api_id
        use_vaec_cie_endpoints? ? settings.tmp_api_id_v2 : settings.tmp_api_id
      end

      def url
        use_vaec_cie_endpoints? ? settings.url_v2 : settings.url
      end
    end
  end
end
