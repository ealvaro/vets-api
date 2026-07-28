# frozen_string_literal: true

require 'sign_in/oauth/configuration'

module SignIn
  module Clear
    class Configuration < SignIn::OAuth::Configuration
      def settings
        IdentitySettings.clear
      end

      def service_name
        'clear'
      end

      def auth_path
        'integrations/oauth2/auth'
      end

      def token_path
        'integrations/oauth2/token'
      end

      def userinfo_path
        'v1/verification_sessions'
      end

      def scope
        'offline openid offline_access'
      end

      def code_challenge_method
        'S256'
      end

      def ssl_options
        {}
      end
    end
  end
end
