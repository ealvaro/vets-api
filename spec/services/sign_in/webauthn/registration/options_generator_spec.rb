# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SignIn::Webauthn::Registration::OptionsGenerator do
  describe '#perform' do
    subject { described_class.new(user_verification:).perform }

    let!(:user_verification) { create(:user_verification) }
    let(:user_account) { user_verification.user_account }
    let(:credential_email) { user_verification.user_credential_email.credential_email }
    let(:challenge_id) { 'some-challenge-id' }
    let(:cache_key) { "#{described_class::CACHE_KEY_PREFIX}:#{challenge_id}" }
    let(:memory_store) { ActiveSupport::Cache::MemoryStore.new }

    before do
      allow(Rails).to receive(:cache).and_return(memory_store)
      allow(SecureRandom).to receive(:uuid).and_return(challenge_id)
    end

    it 'returns the challenge id and caches the challenge under its cache key' do
      options, returned_challenge_id = subject
      expect(returned_challenge_id).to eq(challenge_id)
      expect(Rails.cache.read(cache_key)).to eq(options.challenge)
    end

    context 'when the user account already has a webauthn handle' do
      let(:webauthn_handle) { 'some-webauthn-handle' }

      before { user_account.update!(webauthn_handle:) }

      it 'requests creation options with the expected parameters' do
        expect(WebAuthn::Credential).to receive(:options_for_create).with(
          user: { id: webauthn_handle, name: credential_email, display_name: credential_email },
          authenticator_selection: { resident_key: 'required', user_verification: 'required' },
          attestation: 'none',
          exclude: []
        ).and_call_original

        subject
      end

      it 'does not change the webauthn handle' do
        expect { subject }.not_to(change { user_account.reload.webauthn_handle })
      end
    end

    context 'when the user account does not have a webauthn handle' do
      it 'generates and persists a webauthn handle' do
        expect { subject }.to change { user_account.reload.webauthn_handle }.from(nil)
        expect(user_account.reload.webauthn_handle).to be_present
      end
    end

    context 'when the user account has existing webauthn credentials' do
      let(:existing_credential_id) { 'some-existing-credential-id' }
      let(:webauthn_credential) { create(:webauthn_credential, credential_id: existing_credential_id) }
      let!(:existing_user_verification) do
        create(:user_verification, user_account:, webauthn_credential:, idme_uuid: nil)
      end

      it 'excludes the existing credential ids from the creation options' do
        expect(WebAuthn::Credential).to receive(:options_for_create)
          .with(hash_including(exclude: [existing_credential_id]))
          .and_call_original

        subject
      end
    end
  end
end
