# frozen_string_literal: true

module V2
  module Lorota
    ##
    # A service client for handling HTTP requests to LoROTA API. This needs to be instantiated with a
    # {CheckIn::V2::Session} object so that the {ClaimsToken} can be built and passed to LoROTA for
    # authentication on subsequent calls.
    #
    # @see https://va.ghe.com/software/lorota#lorota-security-details LoROTA security details
    #
    # @example
    #   client = Client.build(check_in: check_in)
    #
    # @!attribute [r] claims_token
    #   @return [V2::Lorota::ClaimsToken]
    # @!attribute [r] check_in
    #   @return [CheckIn::V2::Session]
    # @!attribute [r] settings
    #   @return [Config::Options]
    # @!method url
    #   @return (see Config::Options#url)
    # @!method base_path
    #   @return (see Config::Options#base_path)
    # @!method api_id
    #   @return (see Config::Options#api_id)
    # @!method api_key
    #   @return (see Config::Options#api_key)
    # @!method service_name
    #   @return (see Config::Options#service_name)
    class Client
      extend Forwardable

      attr_reader :claims_token, :check_in, :settings

      def_delegators :settings, :url, :base_path, :api_id, :api_key, :service_name

      ##
      # Builds a Client instance
      #
      # @param opts [Hash] options to create a Client
      # @option opts [CheckIn::V2::Session] :check_in the session object
      #
      # @return [V2::Lorota::Client] an instance of this class
      #
      def self.build(opts = {})
        new(opts)
      end

      def initialize(opts)
        @settings = Settings.check_in.lorota_v2
        @check_in = opts[:check_in]
        @claims_token = ClaimsToken.build(check_in:).sign_assertion
      end

      # POST request to LoROTA token endpoint to get an access token
      #
      # @return [Faraday::Response]
      def token
        connection.post("#{path_prefix}/token") do |req|
          req.headers = default_headers.merge('x-lorota-claims' => claims_token)
          req.body = auth_params.to_json
        end
      end

      # GET request to the data endpoint to get the data stored in LoROTA associated with the uuid
      #
      # @param token [String] LoROTA token
      # @return [Faraday::Response]
      def data(token:)
        connection.get("#{path_prefix}/data/#{check_in.uuid}") do |req|
          req.headers = default_headers.merge('Authorization' => "Bearer #{token}")
        end
      end

      private

      def connection
        Faraday.new(url: host_url) do |conn|
          conn.use(:breakers, service_name:)
          conn.response :raise_custom_error, error_prefix: 'LOROTA-API'
          conn.response :betamocks if mock_enabled?

          conn.adapter Faraday.default_adapter
        end
      end

      # Host portion of the configured `url` (scheme + host + non-default port),
      # stripping any path component. Used as Faraday's base URL so that
      # request paths constructed via #path_prefix don't conflict with a
      # path embedded in the `url` setting.
      def host_url
        uri = URI.parse(url.to_s)
        port_part = uri.port && uri.port != uri.default_port ? ":#{uri.port}" : ''
        "#{uri.scheme}://#{uri.host}#{port_part}"
      end

      # Path prefix to prepend to LoROTA endpoint paths (e.g. `/dev` before
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
      # caller can append "/token", "/data/UUID", etc. cleanly.
      def path_prefix
        url_path = URI.parse(url.to_s).path.to_s.sub(%r{/+\z}, '')
        return url_path unless url_path.empty?

        trimmed = base_path.to_s.gsub(%r{\A/+|/+\z}, '')
        trimmed.empty? ? '' : "/#{trimmed}"
      end

      def default_headers
        {
          'Content-Type' => 'application/json',
          'x-api-key' => api_key,
          'x-apigw-api-id' => api_id
        }
      end

      def auth_params
        {
          lastName: check_in.last_name,
          dob: check_in.dob
        }
      end

      def mock_enabled?
        settings.mock || Flipper.enabled?('check_in_experience_mock_enabled') || false
      end
    end
  end
end
