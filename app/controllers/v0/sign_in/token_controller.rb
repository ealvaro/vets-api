# frozen_string_literal: true

module V0
  module SignIn
    class TokenController < ApplicationController
      skip_before_action :authenticate, only: :token

      def token
        ::SignIn::TokenParamsValidator.new(params: token_params, client_secret_basic_credentials:).perform

        request_attributes = { remote_ip: request.remote_ip, user_agent: request.user_agent }
        response_body = ::SignIn::TokenResponseGenerator.new(params: token_params,
                                                             client_secret_basic_credentials:,
                                                             cookies: token_cookies,
                                                             request_attributes:).perform
        sign_in_logger.info('token')
        StatsD.increment(::SignIn::Constants::Statsd::STATSD_SIS_TOKEN_SUCCESS)

        render json: response_body, status: :ok
      rescue ::SignIn::Errors::StandardError => e
        sign_in_logger.error('token error', exception: e, context: { grant_type: token_params[:grant_type] })
        StatsD.increment(::SignIn::Constants::Statsd::STATSD_SIS_TOKEN_FAILURE)
        render json: { errors: e }, status: :bad_request
      end

      private

      def token_params
        @token_params ||= params.permit(:grant_type, :code, :code_verifier, :client_assertion, :client_assertion_type,
                                        :assertion, :subject_token, :subject_token_type, :actor_token,
                                        :actor_token_type, :client_id)
      end

      def client_secret_basic_credentials
        @client_secret_basic_credentials ||= ::SignIn::ClientSecretBasicCredentialsExtractor.new(
          request:,
          grant_type: token_params[:grant_type],
          client_id: token_params[:client_id]
        ).perform
      end
    end
  end
end
