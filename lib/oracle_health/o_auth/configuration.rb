# frozen_string_literal: true

require 'common/client/configuration/rest'
require 'common/client/middleware/logging'

module OracleHealth
  module OAuth
    class Configuration < Common::Client::Configuration::REST
      def base_path
        IdentitySettings.oracle_health.oauth.uri
      end

      def service_name
        'oracle_health'
      end

      def logging_prefix
        '[OracleHealth][Service]'
      end

      def token_path
        "/tenants/#{tenant_id}/protocols/oauth2/profiles/smart-v1/token"
      end

      def tenant_id
        IdentitySettings.oracle_health.oauth.tenant_id
      end

      def client_id
        IdentitySettings.oracle_health.oauth.client_id
      end

      def client_secret
        IdentitySettings.oracle_health.oauth.client_secret
      end

      def statsd_key_prefix
        'api.oracle_health.oauth'
      end

      def connection
        Faraday.new(base_path, headers: base_request_headers, request: request_options) do |conn|
          conn.use(:breakers, service_name:)
          conn.use Faraday::Response::RaiseError
          conn.adapter Faraday.default_adapter
          conn.response :json
          conn.response :betamocks if IdentitySettings.oracle_health.oauth.mock
        end
      end
    end
  end
end
