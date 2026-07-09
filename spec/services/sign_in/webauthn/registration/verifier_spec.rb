# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SignIn::Webauthn::Registration::Verifier do
  describe '#perform' do
    subject do
      described_class.new(current_user_verification:, registration:, challenge_id:).perform
    end

    let!(:current_user_verification) { create(:user_verification) }
    let(:user_account) { current_user_verification.user_account }
    let(:credential_email) { current_user_verification.user_credential_email.credential_email }
    let(:registration) { { 'id' => 'some-registration' } }
    let(:challenge_id) { 'some-challenge-id' }
    let(:challenge) { 'some-challenge' }
    let(:cache_key) { "#{SignIn::Webauthn::Registration::OptionsGenerator::CACHE_KEY_PREFIX}:#{challenge_id}" }
    let(:memory_store) { ActiveSupport::Cache::MemoryStore.new }

    let(:credential_id) { 'some-credential-id' }
    let(:public_key) { 'some-public-key' }
    let(:sign_count) { 0 }
    let(:transports) { ['internal'] }
    let(:aaguid) { SecureRandom.uuid }
    let(:backed_up) { true }
    let(:backup_eligible) { true }
    let(:attestation_object) { double(aaguid:) }
    let(:credential_response) { double(transports:, attestation_object:) }
    let(:credential) do
      double(
        id: credential_id,
        public_key:,
        sign_count:,
        response: credential_response,
        backed_up?: backed_up,
        backup_eligible?: backup_eligible
      )
    end

    before do
      allow(Rails).to receive(:cache).and_return(memory_store)
      Rails.cache.write(cache_key, challenge)
      allow(WebAuthn::Credential).to receive(:from_create).with(registration).and_return(credential)
      allow(credential).to receive(:verify).and_return(true)
    end

    context 'when the challenge is valid and verification succeeds' do
      it 'verifies the credential against the cached challenge requiring user verification' do
        subject
        expect(credential).to have_received(:verify).with(challenge, user_verification: 'required')
      end

      it 'consumes the cached challenge' do
        subject
        expect(Rails.cache.read(cache_key)).to be_nil
      end

      it 'creates a webauthn credential with the verified attributes' do
        expect { subject }.to change(SignIn::WebauthnCredential, :count).by(1)
        expect(SignIn::WebauthnCredential.last).to have_attributes(
          credential_id:,
          public_key:,
          sign_count:,
          transports:,
          backed_up:,
          backup_eligible:
        )
      end

      it 'creates a user verification for the new credential under the same user account' do
        expect { subject }.to change(UserVerification, :count).by(1)
        expect(SignIn::WebauthnCredential.last.user_verification.user_account).to eq(user_account)
      end

      it 'creates a user credential email copied from the current verification' do
        expect { subject }.to change(UserCredentialEmail, :count).by(1)
        expect(UserCredentialEmail.last.credential_email).to eq(credential_email)
      end

      it 'returns true' do
        expect(subject).to be(true)
      end
    end

    context 'when the challenge is missing or expired' do
      before { Rails.cache.delete(cache_key) }

      it 'does not verify the credential' do
        subject
        expect(credential).not_to have_received(:verify)
      end

      it 'does not create any records and returns false' do
        expect { subject }.to not_change(SignIn::WebauthnCredential, :count)
          .and not_change(UserVerification, :count)
          .and not_change(UserCredentialEmail, :count)
        expect(subject).to be(false)
      end
    end

    context 'when credential verification fails' do
      before { allow(credential).to receive(:verify).and_raise(WebAuthn::VerificationError, 'invalid credential') }

      it 'does not create any records and returns false' do
        expect { subject }.to not_change(SignIn::WebauthnCredential, :count)
          .and not_change(UserVerification, :count)
          .and not_change(UserCredentialEmail, :count)
        expect(subject).to be(false)
      end
    end

    context 'when persisting a record fails inside the transaction' do
      before { allow(UserCredentialEmail).to receive(:create!).and_raise(ActiveRecord::RecordInvalid) }

      it 'rolls back the credential and user verification and returns false' do
        expect { subject }.to not_change(SignIn::WebauthnCredential, :count)
          .and not_change(UserVerification, :count)
        expect(subject).to be(false)
      end
    end
  end
end
