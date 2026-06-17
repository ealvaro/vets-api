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
      before { allow(Flipper).to receive(:enabled?).with(:cve_onboarding_modal, user).and_return(false) }

      it 'returns false even when display_onboarding_flow is true' do
        subject = create(:veteran_onboarding, display_onboarding_flow: true, user_account:)
        expect(subject.show_onboarding_flow_on_login(user)).to be false
      end
    end

    context 'when cve_onboarding_modal is enabled' do
      before { allow(Flipper).to receive(:enabled?).with(:cve_onboarding_modal, user).and_return(true) }

      it 'with cve_onboarding_modal flag on' do
        subject = create(:veteran_onboarding, display_onboarding_flow: true, user_account:)
        expect(subject.show_onboarding_flow_on_login(user)).to be(true)
        subject.update(display_onboarding_flow: false)
        expect(subject.show_onboarding_flow_on_login(user)).to be(false)
      end
    end
  end

  describe '.find_or_create_for_user' do
    context 'with cve_onboarding_modal flag off' do
      before do
        allow(Flipper).to receive(:enabled?).with(:cve_onboarding_modal, user).and_return(false)
      end

      it 'does not create a VeteranOnboarding record' do
        expect do
          result = described_class.find_or_create_for_user(user)
          expect(result).to be_nil
        end.not_to change(VeteranOnboarding, :count).from(0)
      end
    end

    context 'with cve_onboarding_modal flag on' do
      before do
        allow(Flipper).to receive(:enabled?).with(:cve_onboarding_modal, user).and_return(true)
      end

      context 'when user account is not verified' do
        before { user.user_account.update(icn: nil) }

        it 'does not create a veteran onboarding record' do
          expect do
            described_class.find_or_create_for_user(user)
          end.not_to change(VeteranOnboarding, :count).from(0)
        end
      end

      context 'when user account already has an onboarding record' do
        let!(:onboarding_record) { create(:veteran_onboarding, user_account:) }

        it 'returns the record' do
          expect do
            record = described_class.find_or_create_for_user(user)
            expect(record).to eq(onboarding_record)
          end.not_to change(VeteranOnboarding, :count).from(1)
        end
      end

      context 'when user was verified before cutoff time' do
        before { user.user_verification.update(verified_at: 1.hour.ago) }

        it 'does not create a veteran onboarding record' do
          expect do
            record = described_class.find_or_create_for_user(user)
            expect(record).to be_nil
          end.not_to change(VeteranOnboarding, :count).from(0)
        end
      end

      context 'when user was verified after cutoff time' do
        before { user.user_verification.update(verified_at: Time.zone.now) }

        it 'creates and returns a veteran onboarding record' do
          expect do
            record = described_class.find_or_create_for_user(user)
            expect(record.user_account).to eq(user_account)
            expect(record.display_onboarding_flow).to be true
          end.to change(VeteranOnboarding, :count).from(0).to(1)
        end
      end

      context 'when cutoff is not a valid number' do
        before do
          user.user_verification.update(verified_at: 20.minutes.ago)
          allow(Settings).to receive(:veteran_onboarding).and_return(
            OpenStruct.new(
              onboarding_threshold_minutes: 'not a number'
            )
          )
        end

        it 'logs an error and falls back to cutoff time' do
          expect(Rails.logger).to receive(:error).with(
            'VeteranOnboarding - Invalid onboarding threshold: not a number'
          )
          expect do
            record = described_class.find_or_create_for_user(user)
            expect(record).to be_a(VeteranOnboarding)
          end.to change(VeteranOnboarding, :count).from(0).to(1)
        end
      end

      context 'when release date is defined' do
        before do
          user.user_verification.update(verified_at: 3.days.ago)
          allow(Settings).to receive(:veteran_onboarding).and_return(
            OpenStruct.new(
              onboarding_release_date: 'February 1, 2020'
            )
          )
        end

        it 'is used instead of cutoff time' do
          expect do
            record = described_class.find_or_create_for_user(user)
            expect(record.user_account).to eq(user_account)
          end.to change(VeteranOnboarding, :count).from(0).to(1)
        end
      end
    end

    context 'when release date is not a valid date' do
      before do
        user.user_verification.update(verified_at: 3.days.ago)
        allow(Settings).to receive(:veteran_onboarding).and_return(
          OpenStruct.new(
            onboarding_release_date: 'Schmebruary 1, 2020'
          )
        )
      end

      it 'logs an error and falls back to cutoff time' do
        expect(Rails.logger).to receive(:error).with(
          'VeteranOnboarding - Invalid onboarding release date: Schmebruary 1, 2020'
        )
        expect do
          record = described_class.find_or_create_for_user(user)
          expect(record).to be_nil
        end.not_to change(VeteranOnboarding, :count)
      end
    end
  end
end
