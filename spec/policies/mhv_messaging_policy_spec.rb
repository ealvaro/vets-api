# frozen_string_literal: true

require 'rails_helper'
require 'mhv_messaging_policy'

describe MHVMessagingPolicy do
  let(:mhv_messaging) { double('mhv_messaging') }
  let(:expected_error_message) { described_class::SM_ACCESS_LOG_MESSAGE }
  let(:vha_facility_ids) { %w[500] }
  let(:sm_account_created) { true }
  let(:mhv_account_creation) do
    {
      user_profile_id: '12345678',
      patient: true,
      sm_account_created:
    }
  end
  let(:user) do
    create(:user, :loa3, :with_terms_of_use_agreement,
           vha_facility_ids:,
           mhv_account_creation:)
  end

  shared_examples 'messaging policy gate checks' do |policy_method|
    subject { described_class.new(user, mhv_messaging).public_send(policy_method) }

    it 'returns true when user has all required attributes' do
      allow(Rails.logger).to receive(:info)

      expect(subject).to be(true)
      expect(Rails.logger).not_to have_received(:info)
    end

    context 'when user has no mhv_correlation_id' do
      let(:expected_denial_reason) { 'no_mhv_correlation_id' }
      let(:mhv_account_creation) do
        {
          user_profile_id: nil,
          patient: true,
          sm_account_created:
        }
      end

      it 'returns false and logs no_mhv_correlation_id denial reason' do
        allow(Rails.logger).to receive(:info)

        expect(subject).to be(false)

        expect(Rails.logger).to have_received(:info).with(
          expected_error_message,
          hash_including(
            denial_reason: expected_denial_reason,
            user_uuid: user.uuid,
            mhv_id: false.to_s
          )
        )
      end
    end

    context 'when user is not a va_patient' do
      let(:expected_denial_reason) { 'not_va_patient' }
      let(:vha_facility_ids) { [] }

      it 'returns false and logs not_va_patient denial reason' do
        allow(Rails.logger).to receive(:info)

        expect(subject).to be(false)

        expect(Rails.logger).to have_received(:info).with(
          expected_error_message,
          hash_including(
            denial_reason: expected_denial_reason,
            va_patient: false,
            user_uuid: user.uuid,
            mhv_id: user.mhv_correlation_id
          )
        )
      end
    end

    context 'when user has no sm_account_created' do
      let(:expected_denial_reason) { 'sm_account_not_created' }
      let(:sm_account_created) { false }

      it 'returns false and logs sm_account_not_created denial reason' do
        allow(Rails.logger).to receive(:info)

        expect(subject).to be(false)

        expect(Rails.logger).to have_received(:info).with(
          expected_error_message,
          hash_including(
            denial_reason: expected_denial_reason,
            sm_account_created: false,
            user_uuid: user.uuid,
            mhv_id: user.mhv_correlation_id
          )
        )
      end
    end
  end

  describe '#access?' do
    it_behaves_like 'messaging policy gate checks', :access?
  end

  describe '#mobile_access?' do
    it_behaves_like 'messaging policy gate checks', :mobile_access?
  end
end
