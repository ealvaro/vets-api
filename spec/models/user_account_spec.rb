# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UserAccount, type: :model do
  let(:user_account) { create(:user_account, icn:, locked:) }
  let(:icn) { nil }
  let(:locked) { false }

  describe 'validations' do
    describe '#icn' do
      subject { user_account.icn }

      context 'when icn is nil' do
        let(:icn) { nil }

        it 'returns nil' do
          expect(subject).to be_nil
        end
      end

      context 'when icn is unique' do
        let(:icn) { 'kitty-icn' }

        it 'returns given icn value' do
          expect(subject).to eq(icn)
        end
      end

      context 'when icn is not unique' do
        let(:icn) { 'kitty-icn' }
        let(:expected_error_message) { 'Validation failed: Icn has already been taken' }

        before do
          create(:user_account, icn:)
        end

        it 'raises a validation error' do
          expect { subject }.to raise_error(ActiveRecord::RecordInvalid, expected_error_message)
        end
      end
    end
  end

  describe '#locked' do
    subject { user_account.locked }

    context 'user account is not locked by default' do
      it { is_expected.to be false }
    end

    context 'when user account is locked' do
      let(:locked) { true }

      it 'returns true' do
        expect(subject).to be true
      end
    end
  end

  describe '#lock!' do
    subject { user_account.lock! }

    context 'when user account is unlocked' do
      let(:locked) { false }

      it 'locks the user account' do
        subject
        expect(user_account.locked).to be true
      end
    end

    context 'when user account is already locked' do
      let(:locked) { true }

      it 'does not change the locked status' do
        subject
        expect(user_account.locked).to be true
      end
    end
  end

  describe '#unlock!' do
    subject { user_account.unlock! }

    context 'when user account is locked' do
      let(:locked) { true }

      it 'unlocks the user account' do
        subject
        expect(user_account.locked).to be false
      end
    end

    context 'when user account is already unlocked' do
      let(:locked) { false }

      it 'does not change the locked status' do
        subject
        expect(user_account.locked).to be false
      end
    end
  end

  describe '#verified?' do
    subject { user_account.verified? }

    context 'when icn is not defined' do
      let(:icn) { nil }

      it 'returns false' do
        expect(subject).to be false
      end
    end

    context 'when icn is defined' do
      let(:icn) { 'some-icn-value' }

      it 'returns true' do
        expect(subject).to be true
      end
    end
  end

  describe '#needs_accepted_terms_of_use?' do
    subject { user_account.needs_accepted_terms_of_use? }

    context 'when icn is not defined' do
      let(:icn) { nil }

      it 'returns false' do
        expect(subject).to be false
      end
    end

    context 'when icn is defined' do
      let(:icn) { 'some-icn-value' }

      context 'and latest associated terms of use agreement does not exist' do
        let(:terms_of_use_agreement) { nil }

        it 'is true' do
          expect(subject).to be true
        end
      end

      context 'and latest associated terms of use agreement is declined' do
        let!(:terms_of_use_agreement) { create(:terms_of_use_agreement, user_account:, response: 'declined') }

        it 'is true' do
          expect(subject).to be true
        end
      end

      context 'and latest associated terms of use agreement is accepted' do
        let!(:terms_of_use_agreement) { create(:terms_of_use_agreement, user_account:, response: 'accepted') }

        it 'returns true' do
          expect(subject).to be false
        end
      end
    end
  end

  describe '#webauthn_credentials' do
    subject { user_account.webauthn_credentials }

    let(:user_account) { create(:user_account) }

    context 'when the account has verifications with webauthn credentials' do
      let(:webauthn_credential) { create(:webauthn_credential) }
      let!(:user_verification) { create(:user_verification, user_account:, webauthn_credential:, idme_uuid: nil) }

      it 'returns the webauthn credentials associated through user verifications' do
        expect(subject).to contain_exactly(webauthn_credential)
      end
    end

    context 'when the account has no webauthn credentials' do
      it 'returns an empty collection' do
        expect(subject).to be_empty
      end
    end
  end
end
