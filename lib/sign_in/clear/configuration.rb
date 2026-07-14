# frozen_string_literal: true

require 'common/client/configuration/rest'
require 'common/client/middleware/logging'

module SignIn
  module Clear
    class Configuration < Common::Client::Configuration::REST
      def base_path
        IdentitySettings.clear.oauth_url
      end

      def client_id
        IdentitySettings.clear.client_id
      end

      def client_secret
        IdentitySettings.clear.client_secret
      end

      def redirect_uri
        if Settings.review_instance_slug.present?
          "https://staging-api.va.gov/#{Constants::Auth::REVIEW_INSTANCE_CALLBACK_PROXY_PATH}"
        else
          IdentitySettings.clear.redirect_uri
        end
      end

      def verification_session_path(verification_id)
        "v1/verification_sessions/#{verification_id}"
      end

      def grant_type
        'authorization_code'
      end

      def response_type
        'code'
      end

      def code_challenge_method
        'S256'
      end

      def scope
        'offline openid offline_access'
      end

      def auth_path
        'integrations/oauth2/auth'
      end

      def token_path
        'integrations/oauth2/token'
      end

      def service_name
        'clear'
      end

      def log_prefix
        '[SignIn][Clear][Service]'
      end

      def connection
        @connection ||= Faraday.new(
          base_path,
          headers: base_request_headers,
          request: request_options
        ) do |conn|
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
