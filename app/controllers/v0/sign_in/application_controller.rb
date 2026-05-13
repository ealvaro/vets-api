# frozen_string_literal: true

require 'sign_in/logger'

module V0
  module SignIn
    class ApplicationController < ::SignIn::ApplicationController
      private

      def handle_pre_login_error(error, client_id)
        error_code = error.try(:code) || ::SignIn::Constants::ErrorCode::INVALID_REQUEST
        request_id = request.request_id

        if cookie_authentication?(client_id)
          params_hash = { auth: 'fail', code: error_code, request_id: }
          render body: ::SignIn::RedirectUrlGenerator.new(redirect_uri: client_config(client_id).redirect_uri,
                                                          params_hash:).perform,
                 content_type: 'text/html'
        else
          error_params = { error_code:, request_id:, client_id:, occurred_at: Time.current.to_i }

          render body: ::SignIn::RedirectUrlGenerator.new(redirect_uri: sign_in_error_path,
                                                          params_hash: error_params).perform,
                 content_type: 'text/html'
        end
      end

      def anti_csrf_token_param
        params[:anti_csrf_token] || token_cookies[::SignIn::Constants::Auth::ANTI_CSRF_COOKIE_NAME]
      end

      def token_cookies
        @token_cookies ||= defined?(cookies) ? cookies : nil
      end

      def delete_cookies
        cookies.delete(::SignIn::Constants::Auth::ACCESS_TOKEN_COOKIE_NAME, domain: :all)
        cookies.delete(::SignIn::Constants::Auth::REFRESH_TOKEN_COOKIE_NAME)
        cookies.delete(::SignIn::Constants::Auth::ANTI_CSRF_COOKIE_NAME)
        cookies.delete(::SignIn::Constants::Auth::INFO_COOKIE_NAME, domain: IdentitySettings.sign_in.info_cookie_domain)
      end

      def auth_service(type, client_id = nil)
        ::SignIn::AuthenticationServiceRetriever.new(type:, client_config: client_config(client_id)).perform
      end

      def cookie_authentication?(client_id)
        client_config(client_id)&.cookie_auth?
      end

      def client_config(client_id)
        @client_config ||= {}
        @client_config[client_id] ||= ::SignIn::ClientConfig.find_by(client_id:)
      end

      def sign_in_logger
        @sign_in_logger ||= ::SignIn::Logger.new(prefix: 'V0::SignInController')
      end
    end
  end
end
