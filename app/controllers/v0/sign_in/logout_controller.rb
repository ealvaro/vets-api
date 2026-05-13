# frozen_string_literal: true

module V0
  module SignIn
    class LogoutController < ApplicationController
      skip_before_action :authenticate, only: :logout

      def logout # rubocop:disable Metrics/MethodLength
        client_id = params[:client_id].presence
        anti_csrf_token = anti_csrf_token_param.presence

        if client_config(client_id).blank?
          raise ::SignIn::Errors::MalformedParamsError.new message: 'Client id is not valid'
        end

        unless access_token_authenticate(skip_render_error: true)
          raise ::SignIn::Errors::LogoutAuthorizationError.new message: 'Unable to authorize access token'
        end

        session = ::SignIn::OAuthSession.find_by(handle: @access_token.session_handle)
        raise ::SignIn::Errors::SessionNotFoundError.new message: 'Session not found' if session.blank?

        ::SignIn::SessionRevoker.new(access_token: @access_token, anti_csrf_token:).perform
        delete_cookies if token_cookies

        context = {
          client_id: @access_token.client_id,
          session_duration: Time.zone.now.to_i - session.created_at.to_i,
          user_uuid: @access_token.user_uuid,
          session_handle: @access_token.session_handle
        }
        sign_in_logger.info('logout', context)
        StatsD.increment(::SignIn::Constants::Statsd::STATSD_SIS_LOGOUT_SUCCESS)

        logout_redirect = ::SignIn::LogoutRedirectGenerator.new(
          credential_type: session.user_verification.credential_type,
          client_config: client_config(client_id)
        ).perform

        logout_redirect ? redirect_to(logout_redirect) : render(status: :ok)
      rescue ::SignIn::Errors::LogoutAuthorizationError,
             ::SignIn::Errors::SessionNotAuthorizedError,
             ::SignIn::Errors::SessionNotFoundError => e
        sign_in_logger.error('logout error', exception: e, context: { client_id: })
        StatsD.increment(::SignIn::Constants::Statsd::STATSD_SIS_LOGOUT_FAILURE)
        logout_redirect = ::SignIn::LogoutRedirectGenerator.new(client_config: client_config(client_id)).perform

        logout_redirect ? redirect_to(logout_redirect) : render(status: :ok)
      rescue => e
        sign_in_logger.error('logout error', exception: e, context: { client_id: })
        StatsD.increment(::SignIn::Constants::Statsd::STATSD_SIS_LOGOUT_FAILURE)

        render json: { errors: e }, status: :bad_request
      end
    end
  end
end
