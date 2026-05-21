# frozen_string_literal: true

module SignIn
  class UserInfoController < ApplicationController
    service_tag 'identity'

    def show
      authorize access_token, policy_class: SignIn::UserInfoPolicy
      user_info = SignIn::UserInfoGenerator.new(user: current_user).perform

      if user_info.valid?
        render json: serialized_user_info(user_info), status: :ok
      else
        error = user_info.errors.full_messages.join(', ')

        Rails.logger.error('[SignIn][UserInfoController] Invalid user_info', error:)
        render json: { error: }, status: :bad_request
      end
    end

    private

    def serialized_user_info(user_info)
      client_config.oidc? ? user_info.oidc_serializable_hash : user_info.serializable_hash
    end

    def client_config
      @client_config ||= SignIn::ClientConfig.find_by(client_id: access_token.client_id)
    end
  end
end
