# frozen_string_literal: true

module SignIn
  module Webauthn
    module Authentication
      class OptionsGenerator
        CHALLENGE_TTL = 5.minutes
        CACHE_KEY_PREFIX = 'webauthn:auth'

        def perform
          options = WebAuthn::Credential.options_for_get(
            user_verification: 'required',
            rp_id: WebAuthn.configuration.rp_id
          )
          challenge_id = SecureRandom.uuid

          cache_authentication_challenge(options.challenge, challenge_id)

          [options, challenge_id]
        end

        private

        def cache_authentication_challenge(challenge, challenge_id)
          Rails.cache.write("#{CACHE_KEY_PREFIX}:#{challenge_id}", challenge, expires_in: CHALLENGE_TTL)
        end
      end
    end
  end
end
