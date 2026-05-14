# frozen_string_literal: true

module SignIn
  class IdTokenJwtEncoder
    attr_reader :access_token

    def initialize(access_token:)
      @access_token = access_token
    end

    def perform
      jwt_encode_id_token
    end

    private

    def payload
      {
        iss: Constants::AccessToken::ISSUER,
        aud: access_token.audience,
        azp: access_token.client_id,
        sub: access_token.user_uuid,
        exp: access_token.expiration_time.to_i,
        iat: access_token.created_time.to_i,
        auth_time: access_token.created_time.to_i,
        user_attributes: access_token.user_attributes,
        nonce: access_token.nonce
      }.compact
    end

    def jwt_encode_id_token
      JWT.encode(payload, private_key, Constants::AccessToken::JWT_ENCODE_ALGORITHM)
    end

    def private_key
      OpenSSL::PKey::RSA.new(File.read(IdentitySettings.sign_in.jwt_encode_key))
    end
  end
end
