# frozen_string_literal: true

module BID
  module Awards
    # Encoder to be used with BID Awards service
    # @see https://www.jwt.io/introduction#when-to-use-json-web-tokens
    class JwtGenerator
      # expiration period
      VALIDITY_LENGTH = 30.minutes

      # algorithm to be used
      ALGORITHM = 'HS256'

      # Issuer assigned
      ISSUER = 'VAGOV'

      # VBMS user logged in to the application; if no user interaction needs to be a system user
      USER_ID = 'VAGOVSYSACCT'

      # Station for above user
      STATION_ID = '283'

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
          iat: created_time.to_i,
          expires: expiration_time.to_i,
          iss: ISSUER,
          # applicationID MUST be the same as the issuer for tracking purposes
          applicationID: ISSUER,
          userID: USER_ID,
          stationID: STATION_ID
        }
      end

      # retrieve the secret from settings
      def private_key
        Settings.bid.awards.jwt_secret
      end

      # set the token created time
      def created_time
        @created_time = Time.zone.now
      end

      # set the token expiration date
      def expiration_time
        @created_time + VALIDITY_LENGTH
      end
    end
  end
end
