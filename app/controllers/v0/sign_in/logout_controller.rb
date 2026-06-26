# frozen_string_literal: true

module V0
  module SignIn
    class LogoutController < ApplicationController
      skip_before_action :authenticate, only: :logout

      def logout # rubocop:disable Metrics/MethodLength
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
          post_logout_redirect_uri:,
          session_duration: Time.zone.now.to_i - session.created_at.to_i,
          user_uuid: @access_token.user_uuid,
          session_handle: @access_token.session_handle
        }
        sign_in_logger.info(logout_event, context)
        StatsD.increment(logout_success_statsd_key)

        logout_redirect = ::SignIn::LogoutRedirectGenerator.new(
          credential_type: session.user_verification.credential_type,
          client_config: client_config(client_id),
          post_logout_redirect_uri:
        ).perform

        logout_redirect ? redirect_to(logout_redirect) : render(status: :ok)
      rescue ::SignIn::Errors::LogoutAuthorizationError,
             ::SignIn::Errors::SessionNotAuthorizedError,
             ::SignIn::Errors::SessionNotFoundError => e
        log_logout_error(e)

        logout_redirect = ::SignIn::LogoutRedirectGenerator.new(client_config: client_config(client_id),
                                                                post_logout_redirect_uri:).perform

        logout_redirect ? redirect_to(logout_redirect) : render(status: :ok)
      rescue => e
        log_logout_error(e)
        render json: { errors: e }, status: :bad_request
      end

      private

      def client_id
        @client_id ||= params[:client_id].presence
      end

      def post_logout_redirect_uri
        @post_logout_redirect_uri ||= params[:post_logout_redirect_uri].presence
      end

      def logout_event
        'logout'
      end

      def logout_success_statsd_key
        ::SignIn::Constants::Statsd::STATSD_SIS_LOGOUT_SUCCESS
      end

      def logout_failure_statsd_key
        ::SignIn::Constants::Statsd::STATSD_SIS_LOGOUT_FAILURE
      end

      def log_logout_error(error)
        context = { client_id:, post_logout_redirect_uri: }
        sign_in_logger.error("#{logout_event} error", exception: error, context:)
        StatsD.increment(logout_failure_statsd_key)
      end
    end
  end
end
