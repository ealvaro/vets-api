# frozen_string_literal: true

require 'sign_in/oauth/configuration'

module SignIn
  module Logingov
    class Configuration < SignIn::OAuth::Configuration
      def settings
        IdentitySettings.logingov
      end

      def service_name
        'logingov'
      end

      delegate :logout_redirect_uri, to: :settings

      def prompt
        'select_account'
      end

      def auth_path
        'openid_connect/authorize'
      end

      def token_path
        'api/openid_connect/token'
      end

      def logout_path
        'openid_connect/logout'
      end

      def logout_url
        "#{base_path}/#{logout_path}"
      end

      def userinfo_path
        'api/openid_connect/userinfo'
      end

      def public_jwks_path
        '/api/openid_connect/certs'
      end
    end
  end
end
