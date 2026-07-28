# frozen_string_literal: true

require 'common/client/configuration/rest'
require 'common/client/middleware/logging'
require 'sign_in/oauth/constants'

module SignIn
  module OAuth
    class Configuration < Common::Client::Configuration::REST
      delegate :client_id, :client_secret, :client_key_path, :client_cert_path, to: :settings

      def settings
        raise NotImplementedError, "#{self.class} must implement #settings"
      end

      def service_name
        raise NotImplementedError, "#{self.class} must implement #service_name"
      end

      def base_path
        settings.oauth_url
      end

      def auth_url
        "#{base_path}/#{auth_path}"
      end

      def token_url
        "#{base_path}/#{token_path}"
      end

      def redirect_uri
        if Settings.review_instance_slug.present?
          "https://staging-api.va.gov/#{Constants::REVIEW_INSTANCE_CALLBACK_PROXY_PATH}"
        else
          settings.redirect_uri
        end
      end

      def client_assertion_type
        'urn:ietf:params:oauth:client-assertion-type:jwt-bearer'
      end

      def grant_type
        'authorization_code'
      end

      def client_assertion_expiration_seconds
        1000
      end

      def response_type
        'code'
      end

      def jwt_decode_algorithm
        'RS256'
      end

      def ssl_key
        OpenSSL::PKey::RSA.new(File.read(client_key_path))
      end

      def ssl_cert
        OpenSSL::X509::Certificate.new(File.read(client_cert_path))
      end

      def log_credential
        false
      end

      def jwks_cache_key
        "#{service_name}_public_jwks"
      end

      def jwks_cache_expiration
        30.minutes
      end

      def log_prefix
        "[SignIn][#{service_name.camelize}][Service]"
      end

      def ssl_options
        { client_cert: ssl_cert, client_key: ssl_key }
      end

      def connection
        @connection ||= Faraday.new(base_path, headers: base_request_headers, request: request_options,
                                               ssl: ssl_options) do |conn|
          conn.use(:breakers, service_name:)
          conn.use Faraday::Response::RaiseError
          conn.response :snakecase
          conn.response :json, content_type: /\bjson$/
          conn.adapter Faraday.default_adapter
        end
      end
    end
  end
end
