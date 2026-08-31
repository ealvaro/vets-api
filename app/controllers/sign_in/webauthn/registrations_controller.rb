# frozen_string_literal: true

module SignIn
  module Webauthn
    class RegistrationsController < ApplicationController
      rescue_from ActiveRecord::RecordNotFound, with: :credential_not_found
      protect_from_forgery with: :exception
      before_action :set_user
      before_action :set_webauthn_credential, only: :destroy
      after_action :set_csrf_header

      def index
        credentials = @user_account.webauthn_credentials.active

        sign_in_logger.info('webauthn registrations listed', log_context)
        render json: { webauthn_credentials: serialized_credentials(credentials) }, status: :ok
      end

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

      def destroy
        ActiveRecord::Base.transaction do
          @webauthn_credential.revoke!
          revoke_credential_sessions!(@webauthn_credential.user_verification)
        end

        sign_in_logger.info('webauthn registration revoked', log_context)

        render json: signal_payload, status: :ok
      end

      private

      def credential_not_found(exception)
        sign_in_logger.error('webauthn registration revoke error', exception:, context: log_context)
        render json: { error: 'Credential not found' }, status: :not_found
      end

      def revoke_credential_sessions!(user_verification)
        sessions = OAuthSession.where(user_verification:)
        handles = sessions.pluck(:handle)
        sessions.destroy_all
        SessionRecord.sign_out(handles)
      end

      def signal_payload
        {
          rp_id: WebAuthn.configuration.rp_id,
          user_id: @user_account.webauthn_handle,
          all_accepted_credential_ids: @user_account.webauthn_credentials.active.pluck(:credential_id)
        }
      end

      def set_user
        @user_verification = current_user.user_verification
        @user_account = @user_verification.user_account
      end

      def set_webauthn_credential
        @webauthn_credential = @user_account.webauthn_credentials.active.find_by!(credential_id:)
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

      def serialized_credentials(credentials)
        credentials.map do |credential|
          {
            credential_id: credential.credential_id,
            aaguid: credential.aaguid,
            created_at: credential.created_at,
            last_used_at: credential.last_used_at
          }
        end
      end

      def credential_id
        params.require(:credential_id)
      end
    end
  end
end
