# frozen_string_literal: true

require 'sign_in/oauth/configuration'

module SignIn
  module Entra
    class Configuration < SignIn::OAuth::Configuration
      delegate :tenant_id, to: :settings

      def settings
        IdentitySettings.entra
      end

      def service_name
        'entra'
      end

      def base_path
        "#{settings.oauth_url}/#{tenant_id}"
      end

      def auth_path
        'oauth2/v2.0/authorize'
      end

      def token_path
        'oauth2/v2.0/token'
      end

      def public_jwks_path
        'discovery/v2.0/keys'
      end

      def scope
        'openid profile email offline_access'
      end

      def prompt
        'select_account'
      end

      def client_cert_thumbprint
        Base64.urlsafe_encode64(OpenSSL::Digest::SHA1.digest(ssl_cert.to_der), padding: false)
      end

      def ssl_options
        {}
      end
    end
  end
end
