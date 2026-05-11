# frozen_string_literal: true

module Common
  # Shared HS256 JWT generator that services can configure via initializer options.
  class JwtGenerator
    DEFAULT_ALGORITHM = 'HS256'
    DEFAULT_VALIDITY_LENGTH = 900.seconds

    def self.encode_jwt(**)
      new(**).encode_jwt
    end

    def initialize(issuer:, private_key:, **options)
      @issuer = issuer
      @user_id = options.fetch(:user_id, nil)
      @station_id = options.fetch(:station_id, nil)
      @private_key = private_key
      @application_id = options.fetch(:application_id, issuer)
      @algorithm = options.fetch(:algorithm, DEFAULT_ALGORITHM)
      @validity_length = options.fetch(:validity_length, DEFAULT_VALIDITY_LENGTH)
      @include_identity_claims = options.fetch(:include_identity_claims, true)
      @additional_claims = options.fetch(:additional_claims, {})
    end

    def encode_jwt
      JWT.encode(payload, private_key, algorithm, headers)
    end

    private

    attr_reader :additional_claims, :algorithm, :application_id, :include_identity_claims, :issuer,
                :private_key, :station_id, :user_id, :validity_length

    def headers
      { typ: 'JWT', alg: algorithm }
    end

    def payload
      base_payload = {
        jti: SecureRandom.uuid,
        iat: created_time.to_i,
        exp: expiration_time.to_i,
        iss: issuer
      }

      if include_identity_claims
        base_payload[:applicationID] = application_id
        base_payload[:userID] = user_id
        base_payload[:stationID] = station_id
      end

      base_payload.merge(additional_claims)
    end

    def created_time
      @created_time ||= Time.zone.now
    end

    def expiration_time
      @created_time + validity_length
    end
  end
end
