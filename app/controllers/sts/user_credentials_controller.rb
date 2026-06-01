# frozen_string_literal: true

module Sts
  class UserCredentialsController < SignIn::ServiceAccountApplicationController
    service_tag 'identity'

    before_action :validate_requested_by

    rescue_from Common::Exceptions::ParameterMissing, with: ->(e) { handle_error(e, :bad_request) }
    rescue_from Common::Exceptions::BadRequest, with: ->(e) { handle_error(e, :bad_request) }
    rescue_from Common::Exceptions::RecordNotFound, with: ->(e) { handle_error(e, :not_found) }

    def lock_verification
      context = UserCredentialManager.perform_verification_action(action: :lock, type:, credential_id:)
      Rails.logger.info('[Sts::UserCredentialsController] lock_verification success',
                        { requested_by:, **context })
      render json: { requested_by:, **context }, status: :ok
    end

    def unlock_verification
      context = UserCredentialManager.perform_verification_action(action: :unlock, type:, credential_id:)
      Rails.logger.info('[Sts::UserCredentialsController] unlock_verification success',
                        { requested_by:, **context })
      render json: { requested_by:, **context }, status: :ok
    end

    def lock_account
      context = UserCredentialManager.perform_account_action(action: :lock, icn:)
      Rails.logger.info('[Sts::UserCredentialsController] lock_account success', { requested_by:, **context })
      render json: { requested_by:, **context }, status: :ok
    end

    def unlock_account
      context = UserCredentialManager.perform_account_action(action: :unlock, icn:)
      Rails.logger.info('[Sts::UserCredentialsController] unlock_account success', { requested_by:, **context })
      render json: { requested_by:, **context }, status: :ok
    end

    private

    def validate_requested_by
      raise Common::Exceptions::ParameterMissing, 'requested_by' if requested_by.blank?
    end

    def handle_error(exception, status)
      Rails.logger.warn("[Sts::UserCredentialsController] #{action_name} failed",
                        { requested_by:, error: exception.message })
      render json: { error: exception.message }, status:
    end

    def requested_by
      @requested_by ||= params[:requested_by]
    end

    def icn
      @icn ||= @service_account_access_token.user_attributes['icn']
    end

    def type
      @type ||= @service_account_access_token.user_attributes['type']
    end

    def credential_id
      @credential_id ||= @service_account_access_token.user_attributes['credential_id']
    end
  end
end
