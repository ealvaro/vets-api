# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AccreditedRepresentativePortal::ConfigureAccreditedOnlineSubmission2122Service do
  describe '.call' do
    subject(:call_service) do
      described_class.call(poa_codes:, acceptance_mode: 'any_request', default_new_rep_mode: 'any_request')
    end

    context 'with comma-separated string' do
      let!(:org_svs) do
        create(:accredited_organization, poa_code: 'SVS', can_accept_digital_poa_requests: false, name: 'SVS')
      end

      let!(:org_yhz) do
        create(:accredited_organization, poa_code: 'YHZ', can_accept_digital_poa_requests: false, name: 'YHZ')
      end

      let(:poa_codes) { 'SVS,YHZ' }

      it 'updates matching orgs and returns counts' do
        result = call_service

        expect(result).to eq(orgs_updated: 2, reps_updated: 0, org_modes_updated: 2)
        expect(org_svs.reload.can_accept_digital_poa_requests).to be(true)
        expect(org_svs.primary_org_acceptance_mode).to eq('any_request')
        expect(org_svs.default_new_rep_acceptance_mode).to eq('any_request')
        expect(org_yhz.reload.can_accept_digital_poa_requests).to be(true)
        expect(org_yhz.primary_org_acceptance_mode).to eq('any_request')
        expect(org_yhz.default_new_rep_acceptance_mode).to eq('any_request')
      end
    end

    context 'with array input' do
      let!(:org_svs) do
        create(:accredited_organization, poa_code: 'SVS', can_accept_digital_poa_requests: false, name: 'SVS')
      end

      let!(:org_yhz) do
        create(:accredited_organization, poa_code: 'YHZ', can_accept_digital_poa_requests: false, name: 'YHZ')
      end

      let(:poa_codes) { %w[SVS YHZ] }

      it 'accepts arrays and updates matching orgs' do
        result = call_service

        expect(result).to eq(orgs_updated: 2, reps_updated: 0, org_modes_updated: 2)
        expect(org_svs.reload.can_accept_digital_poa_requests).to be(true)
        expect(org_yhz.reload.can_accept_digital_poa_requests).to be(true)
      end
    end

    context 'normalization: whitespace and duplicates' do
      let!(:org_svs) do
        create(:accredited_organization, poa_code: 'SVS', can_accept_digital_poa_requests: false, name: 'SVS')
      end

      let(:poa_codes) { ' SVS ,  SVS  , ' }

      it 'trims and de-dupes, updating only needed rows' do
        result = call_service

        expect(result).to eq(orgs_updated: 1, reps_updated: 0, org_modes_updated: 1)
        expect(org_svs.reload.can_accept_digital_poa_requests).to be(true)
      end
    end

    context 'when blank after normalization' do
      let(:poa_codes) { ' , , ' }

      it 'raises ArgumentError' do
        expect { call_service }.to raise_error(ArgumentError, /POA codes required/)
      end
    end

    context 'when no organizations match' do
      let!(:org_other) do
        create(:accredited_organization, poa_code: 'OTH', can_accept_digital_poa_requests: false, name: 'OTHER')
      end

      let(:poa_codes) { 'NOPE' }

      it 'does not raise and does not update others; returns zero counts' do
        result = nil
        expect { result = call_service }.not_to raise_error

        expect(result).to eq(orgs_updated: 0, reps_updated: 0, org_modes_updated: 0)
        expect(org_other.reload.can_accept_digital_poa_requests).to be(false)
      end
    end

    context 'updates accreditation permissions for active accreditations only' do
      let!(:org) do
        create(:accredited_organization, poa_code: 'SVS', can_accept_digital_poa_requests: false, name: 'SVS')
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

      let(:poa_codes) { 'SVS' }

      let!(:active_needs_update) do
        create(
          :accreditation,
          accredited_organization: org,
          accredited_individual: individual1,
          acceptance_mode: 'no_acceptance',
          deactivated_at: nil
        )
      end

      let!(:active_already_any_request) do
        create(
          :accreditation,
          accredited_organization: org,
          accredited_individual: individual2,
          acceptance_mode: 'any_request',
          deactivated_at: nil
        )
      end

      let!(:deactivated_should_not_change) do
        create(
          :accreditation,
          accredited_organization: org,
          accredited_individual: individual3,
          acceptance_mode: 'no_acceptance',
          deactivated_at: Time.zone.now
        )
      end

      it 'sets acceptance_mode=any_request for active accreditations and returns accurate counts' do
        result = call_service

        expect(result).to eq(orgs_updated: 1, reps_updated: 1, org_modes_updated: 1)

        expect(active_needs_update.reload.acceptance_mode).to eq('any_request')
        expect(active_already_any_request.reload.acceptance_mode).to eq('any_request')
        expect(deactivated_should_not_change.reload.acceptance_mode).to eq('no_acceptance')
      end
    end

    context 'idempotency' do
      let!(:org) do
        create(:accredited_organization, poa_code: 'SVS', can_accept_digital_poa_requests: false, name: 'SVS')
      end

      let!(:individual) do
        create(:accredited_individual, registration_number: 'REP1', individual_type: 'representative')
      end

      let(:poa_codes) { 'SVS' }

      let!(:active_accreditation) do
        create(
          :accreditation,
          accredited_organization: org,
          accredited_individual: individual,
          acceptance_mode: 'no_acceptance',
          deactivated_at: nil
        )
      end

      it 'is safe to call twice; second call updates nothing' do
        first = call_service
        expect(first).to eq(orgs_updated: 1, reps_updated: 1, org_modes_updated: 1)
        expect(org.reload.can_accept_digital_poa_requests).to be(true)
        expect(active_accreditation.reload.acceptance_mode).to eq('any_request')

        second = described_class.call(poa_codes:, acceptance_mode: 'any_request', default_new_rep_mode: 'any_request')
        expect(second).to eq(orgs_updated: 0, reps_updated: 0, org_modes_updated: 0)
        expect(org.reload.can_accept_digital_poa_requests).to be(true)
        expect(active_accreditation.reload.acceptance_mode).to eq('any_request')
      end
    end

    context 'when org update count mismatches expected (fail loudly + rollback)' do
      let!(:org) do
        create(:accredited_organization, poa_code: 'SVS', can_accept_digital_poa_requests: false, name: 'SVS')
      end

      let!(:individual) do
        create(:accredited_individual, registration_number: 'REP1', individual_type: 'representative')
      end

      let(:poa_codes) { 'SVS' }

      let!(:active_accreditation) do
        create(
          :accreditation,
          accredited_organization: org,
          accredited_individual: individual,
          acceptance_mode: 'no_acceptance',
          deactivated_at: nil
        )
      end

      it 'raises and rolls back so accreditation acceptance_mode is not changed' do
        error_class = AccreditedRepresentativePortal::AccreditedPoa2122ServiceHelpers::MismatchError

        allow(described_class).to receive(:enable_online_submission!)
          .and_raise(error_class, 'mismatch')

        expect { call_service }.to raise_error(error_class, /mismatch/i)

        expect(org.reload.can_accept_digital_poa_requests).to be(false)
        expect(active_accreditation.reload.acceptance_mode).to eq('no_acceptance')
      end
    end
  end
end
