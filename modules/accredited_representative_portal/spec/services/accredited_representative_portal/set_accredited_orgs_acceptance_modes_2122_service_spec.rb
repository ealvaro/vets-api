# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AccreditedRepresentativePortal::SetAccreditedOrgsAcceptanceModes2122Service do
  describe '.call' do
    context 'with valid inputs' do
      let!(:org) do
        create(:accredited_organization, poa_code: 'SVS', can_accept_digital_poa_requests: true, name: 'SVS')
      end

      let!(:individual) do
        create(:accredited_individual, registration_number: 'REP1', individual_type: 'representative')
      end

      let!(:active_accreditation) do
        create(
          :accreditation,
          accredited_organization: org,
          accredited_individual: individual,
          acceptance_mode: 'any_request',
          deactivated_at: nil
        )
      end

      it 'updates org columns without changing accreditations' do
        result = described_class.call(poa_codes: 'SVS', primary_mode: 'self_only', default_rep_mode: 'no_acceptance')

        expect(result).to include(org_modes_updated: 1)
        expect(org.reload.primary_org_acceptance_mode).to eq('self_only')
        expect(org.reload.default_new_rep_acceptance_mode).to eq('no_acceptance')
        expect(active_accreditation.reload.acceptance_mode).to eq('any_request')
      end
    end

    context 'with multiple orgs' do
      let!(:org_svs) { create(:accredited_organization, poa_code: 'SVS', name: 'SVS') }
      let!(:org_yhz) { create(:accredited_organization, poa_code: 'YHZ', name: 'YHZ') }

      it 'updates all matching orgs' do
        result = described_class.call(poa_codes: 'SVS,YHZ', primary_mode: 'any_request', default_rep_mode: 'self_only')

        expect(result).to include(org_modes_updated: 2)
        expect(org_svs.reload.primary_org_acceptance_mode).to eq('any_request')
        expect(org_svs.reload.default_new_rep_acceptance_mode).to eq('self_only')
        expect(org_yhz.reload.primary_org_acceptance_mode).to eq('any_request')
        expect(org_yhz.reload.default_new_rep_acceptance_mode).to eq('self_only')
      end
    end

    context 'when blank after normalization' do
      it 'raises ArgumentError' do
        expect do
          described_class.call(poa_codes: ' , , ', primary_mode: 'any_request', default_rep_mode: 'any_request')
        end
          .to raise_error(ArgumentError, /POA codes required/)
      end
    end

    context 'with invalid primary_mode' do
      it 'raises ArgumentError' do
        expect { described_class.call(poa_codes: 'SVS', primary_mode: 'bogus', default_rep_mode: 'any_request') }
          .to raise_error(ArgumentError, /Invalid primary_mode/)
      end
    end

    context 'with invalid default_rep_mode' do
      it 'raises ArgumentError' do
        expect { described_class.call(poa_codes: 'SVS', primary_mode: 'any_request', default_rep_mode: 'bogus') }
          .to raise_error(ArgumentError, /Invalid default_rep_mode/)
      end
    end

    context 'when no organizations match' do
      it 'returns zero updates' do
        result = described_class.call(poa_codes: 'NOPE', primary_mode: 'any_request', default_rep_mode: 'any_request')
        expect(result).to include(org_modes_updated: 0)
      end
    end
  end
end
