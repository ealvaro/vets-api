# frozen_string_literal: true

require 'rails_helper'

describe MHVMedicalRecordsPolicy do
  let(:mhv_medical_records) { double('mhv_medical_records') }
  let(:user_profile_id) { '12345678' }
  let(:premium) { true }
  let(:champ_va) { false }
  let(:patient) { false }
  let(:sm_account_created) { true }
  let(:message) { 'Success' }
  let(:mhv_account_creation) do
    {
      user_profile_id:,
      premium:,
      champ_va:,
      patient:,
      sm_account_created:,
      message:
    }
  end
  let(:user) { create(:user, :loa3, :with_terms_of_use_agreement, mhv_account_creation:) }

  context 'when user is verified' do
    context 'and user is a patient' do
      let(:patient) { true }

      it 'returns true' do
        expect(described_class.new(user, mhv_medical_records).access?).to be(true)
      end
    end

    context 'and user is champ_va eligible' do
      let(:champ_va) { true }
      let(:user) do
        create(:user, :loa3, :with_terms_of_use_agreement,
               mhv_account_creation: { patient: false, champ_va: true })
      end

      it 'returns false and logs not_patient denial reason' do
        expect(Rails.logger).to receive(:info).with(
          'MR ACCESS DENIED',
          hash_including(
            denial_reason: 'not_patient',
            mhv_account_nil: false,
            mhv_account_patient: false,
            loa3: true
          )
        )

        expect(described_class.new(user, mhv_medical_records).access?).to be(false)
      end
    end

    context 'and mhv_user_account is nil due to validation error' do
      let(:user) do
        user = create(:user, :loa3, :with_terms_of_use_agreement)
        allow(user).to receive_messages(mhv_user_account: nil, mhv_user_account_error: 'validation')
        user
      end

      before do
        allow(Rails.logger).to receive(:info)
      end

      it 'returns falsey and logs nil account with validation error category' do
        result = described_class.new(user, mhv_medical_records).access?
        expect(result).to be_falsey

        expect(Rails.logger).to have_received(:info).with(
          'MR ACCESS DENIED',
          hash_including(
            denial_reason: 'account_nil:validation',
            mhv_account_nil: true,
            mhv_account_patient: nil,
            loa3: true
          )
        )
      end
    end

    context 'and user is champ_va eligible with no patient access' do
      let(:champ_va) { true }
      let(:user) do
        create(:user, :loa3, :with_terms_of_use_agreement,
               mhv_account_creation: { patient: false, champ_va: true })
      end

      it 'returns false' do
        # CHAMPVA status does not grant access to medical records
        expect(described_class.new(user, mhv_medical_records).access?).to be(false)
      end
    end

    context 'and user is not a patient' do
      it 'returns false and logs not_patient denial reason' do
        expect(Rails.logger).to receive(:info).with(
          'MR ACCESS DENIED',
          hash_including(
            denial_reason: 'not_patient',
            mhv_account_nil: false,
            mhv_account_patient: false,
            loa3: true
          )
        )

        expect(described_class.new(user, mhv_medical_records).access?).to be(false)
      end
    end
  end

  context 'when user is not verified' do
    let(:user) { create(:user, :loa1) }

    it 'returns false and logs not_loa3 denial reason' do
      allow(Rails.logger).to receive(:info)

      expect(described_class.new(user, mhv_medical_records).access?).to be(false)

      expect(Rails.logger).to have_received(:info).with(
        'MR ACCESS DENIED',
        hash_including(
          denial_reason: 'not_loa3',
          mhv_account_nil: true,
          mhv_account_patient: nil,
          loa3: false
        )
      )
    end

    it 'does not attempt MHV account creation' do
      allow(Rails.logger).to receive(:info)

      expect(MHV::AccountCreation::Service).not_to receive(:new)

      described_class.new(user, mhv_medical_records).access?
    end
  end
end
