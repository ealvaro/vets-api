# frozen_string_literal: true

module V0
  module SignIn
    class RefreshController < ApplicationController
      skip_before_action :authenticate, only: :refresh

      def refresh
        refresh_token = refresh_token_param.presence
        anti_csrf_token = anti_csrf_token_param.presence

        raise ::SignIn::Errors::MalformedParamsError.new message: 'Refresh token is not defined' unless refresh_token

        decrypted_refresh_token = ::SignIn::RefreshTokenDecryptor.new(encrypted_refresh_token: refresh_token).perform
        session_container = ::SignIn::SessionRefresher.new(refresh_token: decrypted_refresh_token,
                                                           anti_csrf_token:).perform
        serializer_response = ::SignIn::TokenSerializer.new(session_container:,
                                                            cookies: token_cookies).perform

        sign_in_logger.info('refresh', session_container.context.merge(safe_keys: [:icn]))
        StatsD.increment(::SignIn::Constants::Statsd::STATSD_SIS_REFRESH_SUCCESS)

        render json: serializer_response, status: :ok
      rescue ::SignIn::Errors::MalformedParamsError => e
        sign_in_logger.error('refresh error', exception: e)
        StatsD.increment(::SignIn::Constants::Statsd::STATSD_SIS_REFRESH_FAILURE)
        render json: { errors: e }, status: :bad_request
      rescue ::SignIn::Errors::StandardError => e
        sign_in_logger.error('refresh error', exception: e)
        StatsD.increment(::SignIn::Constants::Statsd::STATSD_SIS_REFRESH_FAILURE)
        render json: { errors: e }, status: :unauthorized
      end

      private

      def refresh_token_param
        params[:refresh_token] || token_cookies[::SignIn::Constants::Auth::REFRESH_TOKEN_COOKIE_NAME]
      end
    end
  end
end
