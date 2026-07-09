# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SignIn::Webauthn::Authentication::Verifier do
  describe '#perform' do
    subject { described_class.new(authentication, challenge_id).perform }

    let(:authentication) { { 'id' => 'some-authentication' } }
    let(:challenge_id) { 'some-challenge-id' }
    let(:challenge) { 'some-challenge' }
    let(:cache_key) { "#{SignIn::Webauthn::Authentication::OptionsGenerator::CACHE_KEY_PREFIX}:#{challenge_id}" }
    let(:memory_store) { ActiveSupport::Cache::MemoryStore.new }

    let(:credential_id) { Base64.urlsafe_encode64(SecureRandom.random_bytes(16), padding: false) }
    let(:stored_sign_count) { 5 }
    let(:new_sign_count) { 6 }
    let!(:webauthn_credential) { create(:webauthn_credential, credential_id:, sign_count: stored_sign_count) }
    let!(:user_verification) { create(:user_verification, webauthn_credential:, idme_uuid: nil) }
    let!(:client_config) { create(:client_config, client_id: 'vaweb') }

    let(:credential) { double(id: credential_id, sign_count: new_sign_count, verify: true) }
    let(:session_container) { double('SessionContainer') }
    let(:session_creator) { instance_double(SignIn::SessionCreator, perform: session_container) }

    before do
      allow(Rails).to receive(:cache).and_return(memory_store)
      Rails.cache.write(cache_key, challenge)
      allow(WebAuthn::Credential).to receive(:from_get).with(authentication).and_return(credential)
      allow(SignIn::SessionCreator).to receive(:new).and_return(session_creator)
    end

    context 'when the challenge is valid and the assertion verifies' do
      it 'verifies the assertion against the stored credential public key and sign count' do
        subject
        expect(credential).to have_received(:verify).with(
          challenge,
          public_key: webauthn_credential.public_key,
          sign_count: stored_sign_count,
          user_verification: 'required'
        )
      end

      it 'consumes the cached challenge' do
        subject
        expect(Rails.cache.read(cache_key)).to be_nil
      end

      it 'creates a session for the credential and returns the session container' do
        expect(subject).to eq(session_container)
        expect(SignIn::SessionCreator).to have_received(:new)
      end

      it 'stamps last_used_at on the credential' do
        expect { subject }.to change { webauthn_credential.reload.last_used_at }.from(nil)
      end

      context 'when the authenticator sign count is higher than the stored count' do
        it 'updates the stored sign count' do
          expect { subject }.to change { webauthn_credential.reload.sign_count }
            .from(stored_sign_count).to(new_sign_count)
        end
      end

      context 'when the authenticator sign count is not higher than the stored count' do
        let(:new_sign_count) { stored_sign_count }

        it 'does not update the stored sign count' do
          expect { subject }.not_to(change { webauthn_credential.reload.sign_count })
        end
      end
    end

    context 'when the challenge is missing or expired' do
      before { Rails.cache.delete(cache_key) }

      it 'does not create a session and re-raises' do
        expect { subject }.to raise_error(RuntimeError, 'Invalid or expired challenge')
        expect(SignIn::SessionCreator).not_to have_received(:new)
      end
    end

    context 'when the assertion fails to verify' do
      before { allow(credential).to receive(:verify).and_raise(WebAuthn::VerificationError, 'invalid assertion') }

      it 'does not create a session and re-raises' do
        expect { subject }.to raise_error(WebAuthn::VerificationError)
        expect(SignIn::SessionCreator).not_to have_received(:new)
      end

      it 'does not stamp last_used_at' do
        expect { subject }.to raise_error(WebAuthn::VerificationError)
        expect(webauthn_credential.reload.last_used_at).to be_nil
      end
    end
  end
end
