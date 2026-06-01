# frozen_string_literal: true

class UserCredentialManager
  VALID_ACTIONS = %i[lock unlock].freeze
  VALID_TYPES = SignIn::Constants::Auth::CSP_TYPES.freeze

  class << self
    def perform_account_action(action:, icn:)
      normalized_action = validate_action!(action)
      user_account = update_user_account!(icn:, action: normalized_action)

      context = { action:, user_account_id: user_account.id, locked: user_account.locked }
      Rails.logger.info("[UserCredentialManager] UserAccount #{action} success, context: #{context.to_json}")
      context
    end

    def perform_verification_action(action:, type:, credential_id:)
      normalized_action = validate_action!(action)
      user_verification = update_user_verification!(type:, credential_id:, action: normalized_action)

      context = { action:,
                  type: user_verification.credential_type,
                  credential_id: user_verification.credential_identifier,
                  locked: user_verification.locked }
      Rails.logger.info("[UserCredentialManager] UserVerification #{action} success, context: #{context.to_json}")
      context
    end

    private

    def validate_action!(action)
      normalized_action = action&.to_sym

      raise Common::Exceptions::ParameterMissing, 'action' if normalized_action.blank?

      return normalized_action if VALID_ACTIONS.include?(normalized_action)

      raise Common::Exceptions::BadRequest.new(detail: "Action must be one of: #{VALID_ACTIONS.join(', ')}")
    end

    def update_user_account!(icn:, action:)
      raise Common::Exceptions::ParameterMissing, 'icn' if icn.blank?

      user_account = UserAccount.find_by(icn:)
      raise Common::Exceptions::RecordNotFound, icn unless user_account

      user_account.send("#{action}!")
      user_account.reload
    end

    def update_user_verification!(type:, credential_id:, action:)
      raise Common::Exceptions::ParameterMissing, 'type' if type.blank?
      raise Common::Exceptions::ParameterMissing, 'credential_id' if credential_id.blank?

      if VALID_TYPES.exclude?(type)
        raise Common::Exceptions::BadRequest.new(detail: "Type must be one of: #{VALID_TYPES.join(', ')}")
      end

      user_verification = UserVerification.find_by_type(type, credential_id)
      raise Common::Exceptions::RecordNotFound, "type=#{type}, credential_id=#{credential_id}" unless user_verification

      user_verification.send("#{action}!")
      user_verification.reload
    end
  end
end
