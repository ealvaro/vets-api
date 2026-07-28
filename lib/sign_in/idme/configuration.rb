# frozen_string_literal: true

require 'sign_in/oauth/configuration'

module SignIn
  module Idme
    class Configuration < SignIn::OAuth::Configuration
      def settings
        IdentitySettings.idme
      end

      def service_name
        'idme'
      end

      def public_jwks_path
        'oidc/.well-known/jwks'
      end

      def auth_path
        'oauth/authorize'
      end

      def token_path
        'oauth/token'
      end

      def userinfo_path
        'api/public/v3/userinfo.json'
      end

      def sign_up_operation
        'signup'
      end
    end
  end
end
