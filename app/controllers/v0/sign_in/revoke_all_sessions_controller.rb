# frozen_string_literal: true

module V0
  module SignIn
    class RevokeAllSessionsController < ApplicationController
      skip_before_action :authenticate, only: :revoke_all_sessions
      before_action :access_token_authenticate, only: :revoke_all_sessions

      def revoke_all_sessions
        session = ::SignIn::OAuthSession.find_by(handle: @access_token.session_handle)
        raise ::SignIn::Errors::SessionNotFoundError.new message: 'Session not found' if session.blank?

        ::SignIn::RevokeSessionsForUser.new(user_account: session.user_account).perform

        sign_in_logger.info('revoke all sessions', @access_token.to_s)
        StatsD.increment(::SignIn::Constants::Statsd::STATSD_SIS_REVOKE_ALL_SESSIONS_SUCCESS)

        render status: :ok
      rescue ::SignIn::Errors::StandardError => e
        sign_in_logger.error('revoke all sessions error', exception: e)
        StatsD.increment(::SignIn::Constants::Statsd::STATSD_SIS_REVOKE_ALL_SESSIONS_FAILURE)
        render json: { errors: e }, status: :unauthorized
      end
    end
  end
end
