# frozen_string_literal: true

module V0
  module SignIn
    class SessionsController < ApplicationController
      def index
        current_session_handle = @current_user.session_handle
        serialized_sessions = ::SignIn::SessionSerializer.new(
          sessions: ::SignIn::OAuthSession.where(user_account: @current_user.user_account),
          current_session_handle:
        ).perform
        context = { user_uuid: @current_user.uuid, current_session_handle: }
        sign_in_logger.info('index', context)
        StatsD.increment(::SignIn::Constants::Statsd::STATSD_SIS_SESSIONS_SUCCESS)
        render json: { data: serialized_sessions }, status: :ok
      end

      def destroy
        handle = params[:handle].presence
        raise ::SignIn::Errors::MalformedParamsError.new(message: 'Handle is not defined') unless handle

        session = ::SignIn::OAuthSession.find_by(handle:)
        unless session && session.user_account == current_session.user_account
          raise ::SignIn::Errors::SessionNotFoundError.new(message: 'Requested session not found')
        end

        session.destroy!
        ::SignIn::SessionRecord.sign_out(session.handle)

        sign_in_logger.info('destroy', destroy_session_logger_context(session))
        StatsD.increment(::SignIn::Constants::Statsd::STATSD_SIS_DESTROY_SESSION_SUCCESS)

        render status: :ok
      rescue ::SignIn::Errors::MalformedParamsError => e
        sign_in_logger.error('destroy error', exception: e)
        StatsD.increment(::SignIn::Constants::Statsd::STATSD_SIS_DESTROY_SESSION_FAILURE)
        render json: { errors: e }, status: :bad_request
      rescue ::SignIn::Errors::StandardError => e
        sign_in_logger.error('destroy error', exception: e)
        StatsD.increment(::SignIn::Constants::Statsd::STATSD_SIS_DESTROY_SESSION_FAILURE)
        render json: { errors: e }, status: :unauthorized
      end

      private

      def current_session
        @current_session ||= ::SignIn::OAuthSession.find_by(handle: access_token.session_handle)
      end

      def destroy_session_logger_context(session)
        {
          user_uuid: access_token.user_uuid,
          session_handle: session.handle,
          client_id: session.client_id
        }
      end
    end
  end
end
