# frozen_string_literal: true

module V0
  module SignIn
    class LogoutController < ApplicationController
      skip_before_action :authenticate, only: :logout

      def logout
        session = authorize_logout!
        anti_csrf_token = anti_csrf_token_param.presence

        ::SignIn::SessionRevoker.new(access_token: @access_token, anti_csrf_token:).perform
        delete_cookies if token_cookies

        log_logout_success(session)
        perform_logout_redirect(session.user_verification.credential_type)
      rescue ::SignIn::Errors::LogoutAuthorizationError, ::SignIn::Errors::SessionNotAuthorizedError,
             ::SignIn::Errors::SessionNotFoundError => e
        log_logout_error(e)
        delete_cookies if token_cookies
        perform_logout_redirect(logingov_logout_for_okta? ? ::SignIn::Constants::Auth::LOGINGOV : nil)
      rescue => e
        log_logout_error(e)
        render json: { errors: e }, status: :bad_request
      end

      private

      def authorize_logout!
        if client_config(client_id).blank?
          raise ::SignIn::Errors::MalformedParamsError.new message: 'Client id is not valid'
        end

        unless access_token_authenticate(skip_render_error: true, verify_expiration: false)
          raise ::SignIn::Errors::LogoutAuthorizationError.new message: 'Unable to authorize access token'
        end

        session = ::SignIn::OAuthSession.find_by(handle: @access_token.session_handle)
        raise ::SignIn::Errors::SessionNotFoundError.new message: 'Session not found' if session.blank?

        session
      end

      def perform_logout_redirect(credential_type)
        logout_redirect = ::SignIn::LogoutRedirectGenerator.new(
          client_config: client_config(client_id),
          credential_type:,
          post_logout_redirect_uri:
        ).perform

        logout_redirect ? redirect_to(logout_redirect, allow_other_host: true) : render(status: :ok)
      end

      def client_id
        @client_id ||= params[:client_id].presence
      end

      def post_logout_redirect_uri
        @post_logout_redirect_uri ||= params[:post_logout_redirect_uri].presence
      end

      def csp_type
        @csp_type ||= params[:csp_type].presence
      end

      def logout_type
        type = params[:logout_type].presence
        ::SignIn::Constants::Auth::LOGOUT_TYPES.include?(type) ? type : nil
      end

      def okta_client?
        client_id == IdentitySettings.sign_in.okta_client_id
      end

      def logingov_logout_for_okta?
        okta_client? && (csp_type.blank? || csp_type == MPI::Constants::LOGINGOV_IDENTIFIER)
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

      def log_logout_success(session)
        context = {
          client_id: @access_token.client_id,
          post_logout_redirect_uri:,
          csp_type:,
          logout_type:,
          session_duration: Time.zone.now.to_i - session.created_at.to_i,
          user_uuid: @access_token.user_uuid,
          session_handle: @access_token.session_handle
        }
        sign_in_logger.info(logout_event, context)
        StatsD.increment(logout_success_statsd_key)
      end

      def log_logout_error(error)
        context = { client_id:, post_logout_redirect_uri:, csp_type:, logout_type: }
        sign_in_logger.error("#{logout_event} error", exception: error, context:)
        StatsD.increment(logout_failure_statsd_key)
      end
    end
  end
end
