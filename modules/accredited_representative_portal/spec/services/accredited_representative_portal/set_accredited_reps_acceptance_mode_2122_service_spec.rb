# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AccreditedRepresentativePortal::SetAccreditedRepsAcceptanceMode2122Service do
  describe '.call' do
    let!(:org) do
      create(:accredited_organization, poa_code: 'SVS', can_accept_digital_poa_requests: true, name: 'SVS')
    end

    let!(:individual1) do
      create(:accredited_individual, registration_number: 'REP1', individual_type: 'representative')
    end

    let!(:individual2) do
      create(:accredited_individual, registration_number: 'REP2', individual_type: 'representative')
    end

    let!(:individual3) do
      create(:accredited_individual, registration_number: 'REP3', individual_type: 'representative')
    end

    let!(:accreditation1) do
      create(
        :accreditation,
        accredited_organization: org,
        accredited_individual: individual1,
        acceptance_mode: 'any_request',
        deactivated_at: nil
      )
    end

    let!(:accreditation2) do
      create(
        :accreditation,
        accredited_organization: org,
        accredited_individual: individual2,
        acceptance_mode: 'any_request',
        deactivated_at: nil
      )
    end

    let!(:accreditation3_deactivated) do
      create(
        :accreditation,
        accredited_organization: org,
        accredited_individual: individual3,
        acceptance_mode: 'any_request',
        deactivated_at: Time.zone.now
      )
    end

    context 'when setting specific reps to self_only' do
      it 'updates only the specified active reps' do
        result = described_class.call(
          poa_code: 'SVS',
          rep_ids: [individual1.registration_number],
          mode: 'self_only'
        )

        expect(result[:reps_updated]).to eq(1)
        expect(accreditation1.reload.acceptance_mode).to eq('self_only')
        expect(accreditation2.reload.acceptance_mode).to eq('any_request')
      end
    end

    context 'when targeting a deactivated rep' do
      it 'does not update deactivated reps' do
        result = described_class.call(
          poa_code: 'SVS',
          rep_ids: [individual3.registration_number],
          mode: 'self_only'
        )

        expect(result[:reps_updated]).to eq(0)
        expect(accreditation3_deactivated.reload.acceptance_mode).to eq('any_request')
      end
    end

    context 'when setting multiple reps' do
      it 'updates all specified active reps' do
        result = described_class.call(
          poa_code: 'SVS',
          rep_ids: [individual1.registration_number, individual2.registration_number],
          mode: 'no_acceptance'
        )

        expect(result[:reps_updated]).to eq(2)
        expect(accreditation1.reload.acceptance_mode).to eq('no_acceptance')
        expect(accreditation2.reload.acceptance_mode).to eq('no_acceptance')
      end
    end

    context 'when reps are already at the target mode' do
      it 'returns zero updates' do
        result = described_class.call(
          poa_code: 'SVS',
          rep_ids: [individual1.registration_number],
          mode: 'any_request'
        )

        expect(result[:reps_updated]).to eq(0)
      end
    end

    context 'with invalid mode' do
      it 'raises ArgumentError' do
        expect do
          described_class.call(poa_code: 'SVS', rep_ids: [individual1.registration_number], mode: 'invalid')
        end.to raise_error(ArgumentError, /Invalid mode/)
      end
    end

    context 'with blank poa_code' do
      it 'raises ArgumentError' do
        expect do
          described_class.call(poa_code: '', rep_ids: [individual1.registration_number], mode: 'self_only')
        end.to raise_error(ArgumentError, /POA code required/)
      end
    end

    context 'with empty rep_ids' do
      it 'raises ArgumentError' do
        expect do
          described_class.call(poa_code: 'SVS', rep_ids: [], mode: 'self_only')
        end.to raise_error(ArgumentError, /Representative IDs required/)
      end
    end

    context 'with nonexistent org' do
      it 'raises ActiveRecord::RecordNotFound' do
        expect do
          described_class.call(poa_code: 'ZZZ', rep_ids: [individual1.registration_number], mode: 'self_only')
        end.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end
end
