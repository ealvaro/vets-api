# frozen_string_literal: true

module Crm
  class Connection
    extend Forwardable

    attr_reader :settings, :token, :icn

    def_delegators :settings,
                   :base_url,
                   :veis_api_path,
                   :ocp_apim_subscription_key,
                   :service_name,
                   :e_subscription_key,
                   :s_subscription_key

    def initialize(icn:, token:)
      @settings = Settings.ask_va_api.crm_api
      @icn = icn
      @token = token
    end

    def request(method:, endpoint:, payload:, organization:)
      raise ArgumentError, 'organization is required but was nil or blank' if organization.blank?

      uri = build_uri(endpoint, method, organization)
      body = request_body(method, payload, organization)

      conn.public_send(method, uri, body) do |req|
        req.headers = request_headers
      end
    end

    private

    def conn
      @conn ||= Faraday.new(url: base_url) do |f|
        f.use(:breakers, service_name:)
        f.response :betamocks if mock_enabled?
        f.response :raise_custom_error, error_prefix: service_name
        f.adapter Faraday.default_adapter
      end
    end

    def mock_enabled?
      env_check = Settings.vsp_environment.to_s.downcase == 'localhost' # Only enable in localhost

      Settings.betamocks.enabled && Settings.ask_va_api.use_mocks && env_check
    end

    def build_uri(endpoint, method, organization)
      uri = URI.parse("#{veis_api_path}/#{endpoint}")
      uri.query = URI.encode_www_form(organizationName: organization) if method == :put
      uri.to_s
    end

    def request_body(method, payload, organization)
      case method
      when :get
        { organizationName: organization }.merge(payload)
      when :post, :patch, :put
        payload.to_json
      end
    end

    def request_headers
      base = {
        'Content-Type' => 'application/json',
        'Authorization' => "Bearer #{token}",
        'X-VA-ICN' => icn
      }

      env_headers = if Settings.vsp_environment.to_s.downcase == 'production'
                      {
                        'OCP-APIM-Subscription-Key-E' => e_subscription_key,
                        'OCP-APIM-Subscription-Key-S' => s_subscription_key
                      }
                    else
                      {
                        'OCP-APIM-Subscription-Key' => ocp_apim_subscription_key
                      }
                    end

      base.merge(env_headers)
    end
  end
end
