# frozen_string_literal: true

require 'rails_helper'
require 'flipper'
require 'mhv_prescriptions_policy'
require 'mhv/account_creation/service'

describe MHVPrescriptionsPolicy do
  let(:mhv_prescriptions) { double('mhv_prescriptions') }
  let(:patient) { false }
  let(:champ_va) { false }
  let(:mhv_account_creation) { { patient:, champ_va:, sm_account_created: true } }

  describe '#access?' do
    context 'when user is verified' do
      let(:user) { create(:user, :loa3, :with_terms_of_use_agreement, mhv_account_creation:) }

      context 'when user is a patient' do
        let(:patient) { true }

        it 'returns true' do
          expect(described_class.new(user, mhv_prescriptions).access?).to be(true)
        end
      end

      context 'when user is champ_va eligible' do
        let(:champ_va) { true }

        it 'returns true' do
          expect(described_class.new(user, mhv_prescriptions).access?).to be(true)
        end
      end

      context 'when user is both patient and champ_va eligible' do
        let(:patient) { true }
        let(:champ_va) { true }

        it 'returns true' do
          expect(described_class.new(user, mhv_prescriptions).access?).to be(true)
        end
      end

      context 'when user is not a patient or champ_va eligible' do
        let(:patient) { false }
        let(:champ_va) { false }
        let(:user) do
          create(:user, :loa3, :with_terms_of_use_agreement,
                 mhv_account_creation: { patient: false, champ_va: false })
        end

        it 'returns false and logs access denial with diagnostic fields' do
          expect(Rails.logger).to receive(:info).with(
            'RX ACCESS DENIED',
            hash_including(
              denial_reason: 'not_patient_or_champ_va',
              mhv_account_nil: false,
              mhv_account_patient: false,
              mhv_account_champ_va: false,
              loa3: true,
              mhv_id: anything,
              sign_in_service: anything,
              va_facilities: anything,
              va_patient: anything
            )
          )

          expect(described_class.new(user, mhv_prescriptions).access?).to be(false)
        end
      end

      context 'when mhv_user_account is nil due to validation error' do
        let(:user) do
          user = create(:user, :loa3, :with_terms_of_use_agreement)
          allow(user).to receive_messages(mhv_user_account: nil, mhv_user_account_error: 'validation')
          user
        end

        before do
          allow(Rails.logger).to receive(:info)
        end

        it 'returns false and logs nil account with validation error category' do
          expect(described_class.new(user, mhv_prescriptions).access?).to be(false)

          expect(Rails.logger).to have_received(:info).with(
            'RX ACCESS DENIED',
            hash_including(
              denial_reason: 'account_nil:validation',
              mhv_account_nil: true,
              mhv_account_patient: nil,
              mhv_account_champ_va: nil,
              loa3: true
            )
          )
        end
      end

      context 'when mhv_user_account is nil due to MHV client error' do
        let(:user) do
          user = create(:user, :loa3, :with_terms_of_use_agreement)
          allow(user).to receive_messages(mhv_user_account: nil, mhv_user_account_error: 'client')
          user
        end

        before do
          allow(Rails.logger).to receive(:info)
        end

        it 'returns false and logs nil account with client error category' do
          expect(described_class.new(user, mhv_prescriptions).access?).to be(false)

          expect(Rails.logger).to have_received(:info).with(
            'RX ACCESS DENIED',
            hash_including(
              denial_reason: 'account_nil:client',
              mhv_account_nil: true,
              mhv_account_patient: nil
            )
          )
        end
      end
    end

    context 'when user is not verified' do
      let(:user) { create(:user, :loa1) }

      it 'returns false and logs not_loa3 denial reason' do
        allow(Rails.logger).to receive(:info)

        expect(described_class.new(user, mhv_prescriptions).access?).to be(false)

        expect(Rails.logger).to have_received(:info).with(
          'RX ACCESS DENIED',
          hash_including(
            denial_reason: 'not_loa3',
            loa3: false,
            mhv_id: anything,
            sign_in_service: anything,
            va_facilities: anything,
            va_patient: anything
          )
        )
      end

      it 'does not attempt MHV account creation' do
        allow(Rails.logger).to receive(:info)

        expect(MHV::AccountCreation::Service).not_to receive(:new)

        described_class.new(user, mhv_prescriptions).access?
      end
    end
  end
end
