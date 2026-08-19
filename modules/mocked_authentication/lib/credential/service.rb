# frozen_string_literal: true

require 'sign_in/logingov/service'
require 'sign_in/idme/service'
require 'sign_in/entra/service'

module MockedAuthentication
  module Credential
    class Service
      attr_accessor :type

      def render_auth(state:, acr:, operation: SignIn::Constants::Auth::AUTHORIZE, **)
        redirect_uri_with_params(state, acr, operation)
      end

      def token(code, _state = nil)
        {
          access_token: code
        }.merge(logingov_acr(code))
      end

      delegate :normalized_attributes, to: :auth_service

      def user_info(token)
        auth_service.build_user_info(mock_credential_info(token).credential_info)
      end

      private

      def auth_service
        case type
        when SignIn::Constants::Auth::LOGINGOV
          logingov_auth_service
        when SignIn::Constants::Auth::ENTRA
          entra_auth_service
        else
          idme_auth_service(type)
        end
      end

      def redirect_uri_with_params(state, acr, operation)
        "#{redirect_uri}?#{params_hash(state, acr, operation).to_query}"
      end

      def params_hash(state, acr, operation)
        {
          type:,
          acr_values: acr,
          mock_redirect_uri: IdentitySettings.sign_in.mock_redirect_uri,
          state:,
          operation:
        }.compact
      end

      def redirect_uri
        IdentitySettings.sign_in.mock_auth_url
      end

      def logingov_acr(code)
        return {} unless type == SignIn::Constants::Auth::LOGINGOV

        ial =  logingov_credential_has_attributes?(mock_credential_info(code)) ? IAL::TWO : IAL::ONE
        { logingov_acr: get_authn_context(ial) }
      end

      def logingov_credential_has_attributes?(mock_credential_info)
        mock_credential_info.credential_info[:social_security_number].presence
      end

      def get_authn_context(current_ial)
        current_ial == IAL::TWO ? IAL::LOGIN_GOV_IAL2 : IAL::LOGIN_GOV_IAL1
      end

      def mock_credential_info(token)
        @mock_credential_info ||= CredentialInfo.find(token)
      end

      def idme_auth_service(type)
        @idme_auth_service ||= SignIn::Idme::Service.new(type:)
      end

      def logingov_auth_service
        @logingov_auth_service ||= SignIn::Logingov::Service.new
      end

      def entra_auth_service
        @entra_auth_service ||= SignIn::Entra::Service.new
      end
    end
  end
end
