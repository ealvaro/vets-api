# frozen_string_literal: true

module V0
  module SignIn
    class RevokeController < ApplicationController
      skip_before_action :authenticate, only: :revoke

      def revoke
        refresh_token = params[:refresh_token].presence
        anti_csrf_token = params[:anti_csrf_token].presence
        device_secret = params[:device_secret].presence

        raise ::SignIn::Errors::MalformedParamsError.new message: 'Refresh token is not defined' unless refresh_token

        decrypted_refresh_token = ::SignIn::RefreshTokenDecryptor.new(encrypted_refresh_token: refresh_token).perform
        ::SignIn::SessionRevoker.new(refresh_token: decrypted_refresh_token, anti_csrf_token:, device_secret:).perform

        sign_in_logger.info('revoke', decrypted_refresh_token.to_s)
        StatsD.increment(::SignIn::Constants::Statsd::STATSD_SIS_REVOKE_SUCCESS)

        render status: :ok
      rescue ::SignIn::Errors::MalformedParamsError => e
        sign_in_logger.error('revoke error', exception: e)
        StatsD.increment(::SignIn::Constants::Statsd::STATSD_SIS_REVOKE_FAILURE)

        render json: { errors: e }, status: :bad_request
      rescue ::SignIn::Errors::StandardError => e
        sign_in_logger.error('revoke error', exception: e)
        StatsD.increment(::SignIn::Constants::Statsd::STATSD_SIS_REVOKE_FAILURE)

        render json: { errors: e }, status: :unauthorized
      end
    end
  end
end
