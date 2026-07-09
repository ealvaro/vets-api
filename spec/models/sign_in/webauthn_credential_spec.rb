# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SignIn::WebauthnCredential, type: :model do
  describe 'validations' do
    it 'is valid with the factory attributes' do
      expect(build(:webauthn_credential)).to be_valid
    end

    describe 'credential_id' do
      it 'is invalid when blank' do
        expect(build(:webauthn_credential, credential_id: nil)).not_to be_valid
      end

      it 'is invalid when not unique' do
        create(:webauthn_credential, credential_id: 'some-credential-id')

        expect(build(:webauthn_credential, credential_id: 'some-credential-id')).not_to be_valid
      end
    end

    describe 'public_key' do
      it 'is invalid when blank' do
        expect(build(:webauthn_credential, public_key: nil)).not_to be_valid
      end
    end

    describe 'sign_count' do
      it 'is invalid when nil' do
        expect(build(:webauthn_credential, sign_count: nil)).not_to be_valid
      end
    end

    describe 'transports' do
      it 'is valid when empty' do
        expect(build(:webauthn_credential, transports: [])).to be_valid
      end
    end

    describe 'backed_up and backup_eligible' do
      it 'is invalid when backed_up is nil' do
        expect(build(:webauthn_credential, backed_up: nil)).not_to be_valid
      end

      it 'is invalid when backup_eligible is nil' do
        expect(build(:webauthn_credential, backup_eligible: nil)).not_to be_valid
      end
    end
  end

  describe '#user_verification' do
    subject { webauthn_credential.user_verification }

    let(:webauthn_credential) { create(:webauthn_credential) }

    context 'when a user verification references the credential' do
      let!(:user_verification) { create(:user_verification, webauthn_credential:, idme_uuid: nil) }

      it 'returns the user verification' do
        expect(subject).to eq(user_verification)
      end
    end

    context 'when no user verification references the credential' do
      it 'returns nil' do
        expect(subject).to be_nil
      end
    end
  end
end
