# frozen_string_literal: true

module SignIn
  module Webauthn
    class AuthenticationsController < ApplicationController
      skip_before_action :authenticate
      after_action :set_csrf_header

      def options
        options, challenge_id = Authentication::OptionsGenerator.new.perform

        sign_in_logger.info('webauthn authentication options generated')
        render json: { options:, challenge_id: }, status: :ok
      rescue => e
        sign_in_logger.error('webauthn authentication options error', exception: e)
        render json: { error: e.message }, status: :unprocessable_entity
      end

      def verify
        session_container = Authentication::Verifier.new(authentication_params[:attest], challenge_id,
                                                         request_attributes).perform
        response_body = TokenSerializer.new(session_container:, cookies:).perform
        response_body[:verified] = true

        user_account = session_container.session.user_account
        sign_in_logger.info('webauthn authentication verified', user_account_id: user_account.id, icn: user_account.icn)
        render json: response_body, status: :ok
      rescue => e
        sign_in_logger.error('webauthn authentication verify error', exception: e)
        render json: { error: e.message }, status: :unprocessable_entity
      end

      private

      def authentication_params
        params.require(:authentication)
      end

      def challenge_id
        params.require(:challenge_id)
      end

      def request_attributes
        { remote_ip: request.remote_ip, user_agent: request.user_agent }
      end
    end
  end
end
