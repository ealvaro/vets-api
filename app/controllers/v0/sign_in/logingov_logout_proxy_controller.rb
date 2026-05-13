# frozen_string_literal: true

module V0
  module SignIn
    class LogingovLogoutProxyController < ApplicationController
      skip_before_action :authenticate, only: :logingov_logout_proxy

      def logingov_logout_proxy
        state = params[:state].presence

        raise ::SignIn::Errors::MalformedParamsError.new message: 'State is not defined' unless state

        logingov_service = auth_service(::SignIn::Constants::Auth::LOGINGOV)
        state_payload = logingov_service.decode_logout_state(state)
        validate_logout_redirect_uri!(state_payload['client_id'], state_payload['logout_redirect'])

        render body: logingov_service.render_logout_redirect(state), content_type: 'text/html'
      rescue => e
        sign_in_logger.error('logingov_logout_proxy error', exception: e)

        render json: { errors: e }, status: :bad_request
      end

      private

      def validate_logout_redirect_uri!(client_id, uri)
        config = client_config(client_id)
        if config.blank? || config.logout_redirect_uri != uri
          raise ::SignIn::Errors::InvalidLogoutRedirectUriError.new message: 'Logout redirect URI is not registered'
        end
      end
    end
  end
end
