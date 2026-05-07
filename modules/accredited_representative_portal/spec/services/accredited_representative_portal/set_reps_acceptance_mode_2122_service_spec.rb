# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AccreditedRepresentativePortal::SetRepsAcceptanceMode2122Service do
  describe '.call' do
    let!(:org) { create(:veteran_organization, poa: 'SVS', can_accept_digital_poa_requests: true, name: 'SVS') }

    let!(:rep1) do
      create(:veteran_organization_representative, organization: org, acceptance_mode: 'any_request',
                                                   deactivated_at: nil)
    end

    let!(:rep2) do
      create(:veteran_organization_representative, organization: org, acceptance_mode: 'any_request',
                                                   deactivated_at: nil)
    end

    let!(:rep3_deactivated) do
      create(:veteran_organization_representative, organization: org, acceptance_mode: 'any_request',
                                                   deactivated_at: Time.zone.now)
    end

    context 'when setting specific reps to self_only' do
      it 'updates only the specified active reps' do
        result = described_class.call(
          poa_code: 'SVS',
          rep_ids: [rep1.representative_id],
          mode: 'self_only'
        )

        expect(result[:reps_updated]).to eq(1)
        expect(rep1.reload.acceptance_mode).to eq('self_only')
        expect(rep2.reload.acceptance_mode).to eq('any_request')
      end
    end

    context 'when targeting a deactivated rep' do
      it 'does not update deactivated reps' do
        result = described_class.call(
          poa_code: 'SVS',
          rep_ids: [rep3_deactivated.representative_id],
          mode: 'self_only'
        )

        expect(result[:reps_updated]).to eq(0)
        expect(rep3_deactivated.reload.acceptance_mode).to eq('any_request')
      end
    end

    context 'when setting multiple reps' do
      it 'updates all specified active reps' do
        result = described_class.call(
          poa_code: 'SVS',
          rep_ids: [rep1.representative_id, rep2.representative_id],
          mode: 'no_acceptance'
        )

        expect(result[:reps_updated]).to eq(2)
        expect(rep1.reload.acceptance_mode).to eq('no_acceptance')
        expect(rep2.reload.acceptance_mode).to eq('no_acceptance')
      end
    end

    context 'when reps are already at the target mode' do
      it 'returns zero updates' do
        result = described_class.call(
          poa_code: 'SVS',
          rep_ids: [rep1.representative_id],
          mode: 'any_request'
        )

        expect(result[:reps_updated]).to eq(0)
      end
    end

    context 'with invalid mode' do
      it 'raises ArgumentError' do
        expect do
          described_class.call(poa_code: 'SVS', rep_ids: [rep1.representative_id], mode: 'invalid')
        end.to raise_error(ArgumentError, /Invalid mode/)
      end
    end

    context 'with blank poa_code' do
      it 'raises ArgumentError' do
        expect do
          described_class.call(poa_code: '', rep_ids: [rep1.representative_id], mode: 'self_only')
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
          described_class.call(poa_code: 'ZZZ', rep_ids: [rep1.representative_id], mode: 'self_only')
        end.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end
end
