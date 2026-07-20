# frozen_string_literal: true

module BEP
  module Persons
    # Encoder to be used with BEP Persons service
    # @see https://www.jwt.io/introduction#when-to-use-json-web-tokens
    class JwtGenerator
      # expiration period
      VALIDITY_LENGTH = 30.minutes.to_i

      # algorithm to be used
      ALGORITHM = 'HS256'

      # Issuer assigned
      ISSUER = 'vets-api'

      # VBMS user logged in to the application; if no user interaction needs to be a system user
      USER_ID = 'VAGOVSYSACCT'

      # Station for above user
      STATION_ID = '283'

      # Application user is registered under
      # @see https://va.ghe.com/software/va.gov-team/issues/139913
      APPLICATION_ID = 'VBMS'

      # static method
      # @see #encode_jwt
      def self.encode_jwt
        new.encode_jwt
      end

      # Returns a JWT token for use in Bearer auth
      def encode_jwt
        JWT.encode(payload, private_key, ALGORITHM, headers)
      end

      private

      # Returns the headers for the JWT token
      def headers
        { typ: 'JWT', alg: ALGORITHM }
      end

      # the generated payload to be encoded
      def payload
        {
          jti: SecureRandom.uuid, # random id to identify a unique JWT
          iat: Time.now.to_i,
          exp: Time.now.to_i + VALIDITY_LENGTH,
          iss: ISSUER,
          applicationID: APPLICATION_ID,
          userID: USER_ID,
          stationID: STATION_ID
        }
      end

      # retrieve the secret from settings
      def private_key
        Settings.bep.persons.jwt_secret
      end
    end
  end
end
