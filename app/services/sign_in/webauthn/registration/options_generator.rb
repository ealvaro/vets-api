# frozen_string_literal: true

module SignIn
  module Webauthn
    module Registration
      class OptionsGenerator
        CHALLENGE_TTL = 5.minutes
        CACHE_KEY_PREFIX = 'webauthn:reg'

        def initialize(user_verification:)
          @user_verification = user_verification
        end

        def perform
          ensure_webauthn_handle

          options = WebAuthn::Credential.options_for_create(**pubkey_options_params)
          challenge_id = SecureRandom.uuid

          cache_registration_challenge(options.challenge, challenge_id)

          [options, challenge_id]
        end

        private

        attr_reader :user_verification

        def pubkey_options_params
          {
            user: {
              id: user_account.webauthn_handle,
              name: user_verification.user_credential_email.credential_email,
              display_name: user_verification.user_credential_email.credential_email
            },
            authenticator_selection: {
              resident_key: 'required',
              user_verification: 'required'
            },
            attestation: 'none',
            exclude: existing_credentials
          }
        end

        def ensure_webauthn_handle
          return if user_account.webauthn_handle.present?

          user_account.update!(webauthn_handle: Base64.urlsafe_encode64(SecureRandom.random_bytes(32), padding: false))
        end

        def cache_registration_challenge(challenge, challenge_id)
          Rails.cache.write("#{CACHE_KEY_PREFIX}:#{challenge_id}", challenge, expires_in: CHALLENGE_TTL)
        end

        def user_account
          @user_account ||= user_verification.user_account
        end

        def existing_credentials
          user_account.webauthn_credentials.active.pluck(:credential_id)
        end
      end
    end
  end
end
