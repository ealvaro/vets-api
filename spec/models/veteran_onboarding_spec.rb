# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VeteranOnboarding, type: :model do
  let(:user) { create(:user, :loa3) }
  let(:user_account) { user.user_account }

  describe 'validations' do
    it 'validates presence of user_account_uuid' do
      subject = described_class.new(user_account: nil)
      expect(subject).not_to be_valid
      expect(subject.errors.details[:user_account]).to include(error: :blank)
    end

    it 'validates uniqueness of user_account_uuid' do
      described_class.create!(user_account:)
      subject = described_class.new(user_account:)
      expect(subject).not_to be_valid
      expect(subject.errors.details[:user_account]).to include(error: :taken, value: user_account)
    end
  end

  describe '#show_onboarding_flow_on_login' do
    context 'with cve_onboarding_modal flag off' do
      before { allow(Flipper).to receive(:enabled?).with(:cve_onboarding_modal, anything).and_return(false) }

      it 'returns false even when display_onboarding_flow is true' do
        subject = create(:veteran_onboarding, display_onboarding_flow: true, user_account:)
        expect(subject.show_onboarding_flow_on_login).to be false
      end
    end

    context 'when cve_onboarding_modal is enabled' do
      before { allow(Flipper).to receive(:enabled?).with(:cve_onboarding_modal, anything).and_return(true) }

      it 'with cve_onboarding_modal flag on' do
        subject = create(:veteran_onboarding, display_onboarding_flow: true, user_account:)
        expect(subject.show_onboarding_flow_on_login).to be(true)
        subject.update(display_onboarding_flow: false)
        expect(subject.show_onboarding_flow_on_login).to be(false)
      end
    end
  end

  describe '.create_for_user_account' do
    context 'with cve_onboarding_modal flag off' do
      before do
        allow(Flipper).to receive(:enabled?).with(:cve_onboarding_modal, anything).and_return(false)
      end

      it 'does not create a VeteranOnboarding record' do
        result = described_class.create_for_user_account(user_account)
        expect(result).to be_nil
      end
    end

    context 'with cve_onboarding_modal flag on' do
      before do
        allow(Flipper).to receive(:enabled?).with(:cve_onboarding_modal, anything).and_return(true)
      end

      context 'when user account is not verified' do
        before { user.user_account.update(icn: nil) }

        it 'does not create a veteran onboarding record' do
          expect(Rails.logger).to receive(:info).with("VeteranOnboarding - Account not verified: #{user_account.id}")
          expect do
            described_class.create_for_user_account(user_account)
          end.not_to change(VeteranOnboarding, :count).from(0)
        end
      end

      context 'when user account already has an onboarding record' do
        before { create(:veteran_onboarding, user_account:) }

        it 'does not create a veteran onboarding record' do
          expect(Rails.logger).to receive(:error).with(
            "VeteranOnboarding - Error creating record for account #{user_account.id}: " \
            'Validation failed: User account has already been taken'
          )
          expect do
            record = described_class.create_for_user_account(user_account)
            expect(record).to be_nil
          end.not_to change(VeteranOnboarding, :count).from(1)
        end
      end

      context 'when user account is verified' do
        it 'creates and returns a veteran onboarding record' do
          expect do
            record = described_class.create_for_user_account(user_account)
            expect(record.user_account).to eq(user_account)
            expect(record.display_onboarding_flow).to be true
          end.to change(VeteranOnboarding, :count).from(0).to(1)
        end
      end
    end
  end
end
