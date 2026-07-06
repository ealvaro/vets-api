# frozen_string_literal: true

require 'rails_helper'

# Proves vets-api's encrypted session cookies survive the Rails 7.2 -> 8.1 upgrade
# (current key, old-key rotation, and a real 7.2-minted cookie). Mirrors
# config/initializers/cookie_rotation.rb. Context (why this matters — mass-logout
# risk): https://va.ghe.com/software/vets-api/pull/29083
RSpec.describe 'Cookie / session decryption compatibility', type: :request do
  let(:cipher) { 'aes-256-gcm' }
  let(:salt)   { Rails.application.config.action_dispatch.authenticated_encrypted_cookie_salt }
  let(:key_len) { ActiveSupport::MessageEncryptor.key_len(cipher) }

  let(:session_payload) { { 'warden.user.user.key' => 'abc-123', 'session_id' => 'sid-xyz', 'foo' => 1 } }

  def encryptor_for(secret_key_base, key_salt: salt)
    secret = ActiveSupport::KeyGenerator.new(secret_key_base, iterations: 1000)
                                        .generate_key(key_salt, key_len)
    ActiveSupport::MessageEncryptor.new(secret, cipher:, serializer: Marshal)
  end

  describe 'current-key cookies (the mass-logout risk)' do
    it 'round-trips an encrypted session payload through the real key-derivation path' do
      enc = encryptor_for(Settings.secret_key_base)
      token = enc.encrypt_and_sign(session_payload)
      expect(enc.decrypt_and_verify(token)).to eq(session_payload)
    end

    it 'uses AES-256-GCM key length (32 bytes) — unchanged on 8.1' do
      expect(key_len).to eq(32)
    end
  end

  describe 'rotation fallback (cookies minted under old_secret_key_base)' do
    it 'still decrypts a cookie encrypted under the OLD key via the rotation derivation' do
      old_enc = encryptor_for(Settings.old_secret_key_base)
      token_from_old_key = old_enc.encrypt_and_sign(session_payload)

      rotation_enc = encryptor_for(Settings.old_secret_key_base)
      expect(rotation_enc.decrypt_and_verify(token_from_old_key)).to eq(session_payload)
    end
  end

  # Fixture minted by real Rails 7.2.3.1 code with the committed test secret_key_base.
  # To regenerate if that secret ever changes, on a 7.2 checkout:
  #   secret = ActiveSupport::KeyGenerator.new(Settings.secret_key_base, iterations: 1000)
  #                                        .generate_key(salt, key_len)
  #   Base64.strict_encode64(
  #     ActiveSupport::MessageEncryptor.new(secret, cipher: 'aes-256-gcm', serializer: Marshal)
  #       .encrypt_and_sign(session_payload))
  describe 'a real 7.2-minted cookie decrypts on 8.1 (cross-version)' do
    let(:frozen_72_cookie) do
      'K21FNG1rZENQckJNQVdCODhINXlSS21tYUNCRlJUNDd0ZU8rd0d2OGR4aGxPeTAzdjZmVHY4emZWS2tBUUtwWGVC' \
        'bXgzUXhTaDRvL2phN2t5K09iODYvZDMzVHhFaDZBOFVDb3NZOWl0TDhrUW1GM1JHVm42cEk9LS1lWlBEeVc2d2No' \
        'S3MvdlJNLS1vK0JZazk0NU9FRG8yMjBYdnVselp3PT0='
    end

    it 'decrypts a genuine Rails 7.2-encrypted cookie to the original payload' do
      raw = Base64.decode64(frozen_72_cookie)
      enc = encryptor_for(Settings.secret_key_base)
      expect(enc.decrypt_and_verify(raw)).to eq(session_payload)
    end
  end
end
