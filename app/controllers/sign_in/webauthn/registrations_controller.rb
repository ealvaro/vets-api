# frozen_string_literal: true

module SignIn
  module Webauthn
    class RegistrationsController < ApplicationController
      protect_from_forgery with: :exception
      before_action :set_user
      after_action :set_csrf_header

      def options
        options, challenge_id = Registration::OptionsGenerator.new(user_verification: @user_verification).perform

        sign_in_logger.info('webauthn registration options generated', log_context)
        render json: { options:, challenge_id: }, status: :ok
      rescue => e
        sign_in_logger.error('webauthn registration options error', exception: e, context: log_context)
        render json: { error: e.message }, status: :unprocessable_entity
      end

      def verify
        verified = Registration::Verifier.new(
          current_user_verification: @user_verification,
          registration: registration_params,
          challenge_id:
        ).perform

        sign_in_logger.info('webauthn registration verified', log_context)
        render json: { verified: }, status: :ok
      rescue => e
        sign_in_logger.error('webauthn registration verify error', exception: e, context: log_context)
        render json: { error: e.message }, status: :unprocessable_entity
      end

      private

      def set_user
        @user_verification = current_user.user_verification
        @user_account = @user_verification.user_account
      end

      def log_context
        { user_verification_id: @user_verification.id, user_account_id: @user_account.id, icn: @user_account.icn }
      end

      def registration_params
        params.require(:registration)
      end

      def challenge_id
        params.require(:challenge_id)
      end
    end
  end
end
