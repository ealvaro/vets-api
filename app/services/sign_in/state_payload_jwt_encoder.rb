# frozen_string_literal: true

module SignIn
  class StatePayloadJwtEncoder
    attr_reader(
      :acr,
      :client_config,
      :type,
      :code_challenge,
      :code_challenge_method,
      :client_state,
      :scope,
      :operation,
      :nonce,
      :redirect_uri,
      :authorize_sso_id,
      :app_name
    )

    # rubocop:disable Metrics/ParameterLists
    def initialize(code_challenge:, code_challenge_method:, acr:, client_config:, type:, operation:, scope: nil,
                   client_state: nil, nonce: nil, redirect_uri: nil, authorize_sso_id: nil, app_name: nil)
      @acr = acr
      @client_config = client_config
      @client_state = client_state
      @code_challenge = code_challenge
      @code_challenge_method = code_challenge_method
      @type = type
      @scope = scope
      @operation = operation
      @nonce = nonce
      @redirect_uri = redirect_uri || set_redirect_uri
      @authorize_sso_id = authorize_sso_id
      @app_name = app_name
    end
    # rubocop:enable Metrics/ParameterLists

    def perform
      validate_pkce_params! if client_config.pkce?
      validate_scope!
      validate_state_payload!
      save_state_code
      jwt_encode_state_payload
    end

    private

    def validate_pkce_params!
      validate_code_challenge_method!
      validate_code_challenge!
    end

    def validate_scope!
      raise Errors::InvalidScope.new message: 'Scope is not valid for Client' if sso_not_enabled_for_device_sso_scope?
    end

    def validate_code_challenge_method!
      if code_challenge_method != Constants::Auth::CODE_CHALLENGE_METHOD
        raise Errors::CodeChallengeMethodMismatchError.new message: 'Code Challenge Method is not valid'
      end
    end

    def validate_code_challenge!
      raise Errors::CodeChallengeMalformedError.new message: 'Code Challenge is not valid' if code_challenge.blank?
    end

    def validate_state_payload!
      state_payload
    rescue ActiveModel::ValidationError
      raise Errors::StatePayloadError.new message: 'Attributes are not valid'
    end

    def jwt_encode_state_payload
      JWT.encode(jwt_payload, private_key, Constants::Auth::JWT_ENCODE_ALGORITHM)
    end

    def save_state_code
      StateCode.new(code: state_code).save!
    end

    def jwt_payload
      {
        acr: state_payload.acr,
        type: state_payload.type,
        client_id: state_payload.client_id,
        code_challenge: state_payload.code_challenge,
        client_state: state_payload.client_state,
        code: state_payload.code,
        created_at: state_payload.created_at,
        scope: state_payload.scope,
        operation: state_payload.operation,
        nonce: state_payload.nonce,
        redirect_uri:,
        authorize_sso_id: state_payload.authorize_sso_id,
        app_name: state_payload.app_name
      }
    end

    def state_payload
      @state_payload ||= StatePayload.new(acr:,
                                          type:,
                                          client_id: client_config.client_id,
                                          code_challenge: remove_base64_padding(code_challenge),
                                          code: state_code,
                                          client_state:,
                                          scope:,
                                          operation:,
                                          nonce:,
                                          redirect_uri:,
                                          authorize_sso_id:,
                                          app_name:)
    end

    def state_code
      @state_code ||= SecureRandom.hex
    end

    def set_redirect_uri
      return if Settings.review_instance_slug.blank?

      host = "#{Settings.review_instance_slug}-api.#{Constants::Auth::REVIEW_INSTANCES_HOST}"
      path = Constants::Auth::CALLBACK_PATH

      URI::HTTPS.build(host:, path:).to_s
    end

    def sso_not_enabled_for_device_sso_scope?
      scope == Constants::Auth::DEVICE_SSO && !client_config.api_sso_enabled?
    end

    def remove_base64_padding(data)
      return unless client_config.pkce? && data

      Base64.urlsafe_encode64(Base64.urlsafe_decode64(data.to_s), padding: false)
    rescue ArgumentError
      raise Errors::CodeChallengeMalformedError.new message: 'Code Challenge is not valid'
    end

    def private_key
      OpenSSL::PKey::RSA.new(File.read(IdentitySettings.sign_in.jwt_encode_key))
    end
  end
end
