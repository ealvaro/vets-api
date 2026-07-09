# frozen_string_literal: true

FactoryBot.define do
  factory :webauthn_credential, class: 'SignIn::WebauthnCredential' do
    credential_id { SecureRandom.uuid }
    public_key { SecureRandom.base64 }
    sign_count { 0 }
    transports { ['internal'] }
    aaguid { SecureRandom.uuid }
    backed_up { false }
    backup_eligible { false }
  end
end
