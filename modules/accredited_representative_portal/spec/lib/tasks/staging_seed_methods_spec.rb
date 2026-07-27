# frozen_string_literal: true

require 'rails_helper'
require_relative '../../../lib/tasks/seed/staging_seed'

RSpec.describe AccreditedRepresentativePortal::StagingSeeds do
  let(:seeds) { described_class }

  describe 'shared FK identifier helpers' do
    it 'reads the poa code from accredited or legacy organizations' do
      expect(seeds.send(:org_poa_code, build(:accredited_organization, poa_code: 'ABC'))).to eq('ABC')
      expect(seeds.send(:org_poa_code, build(:organization, poa: 'XYZ'))).to eq('XYZ')
    end

    it 'reads the registration number from accredited or legacy representatives' do
      accredited = build(:accredited_individual, registration_number: '111')
      expect(seeds.send(:rep_registration_number, accredited)).to eq('111')
      expect(seeds.send(:rep_registration_number, build(:representative, representative_id: '222'))).to eq('222')
    end
  end

  describe '#fetch_organizations' do
    context 'when the flag is off' do
      before { allow(AccreditedRepresentativePortal).to receive(:use_accredited_models?).and_return(false) }

      let!(:ct) { create(:organization, poa: '008', can_accept_digital_poa_requests: true) }

      it 'returns legacy organizations' do
        result = seeds.send(:fetch_organizations)

        expect(result[:ct]).to eq(ct)
        expect(result[:ct]).to be_a(Veteran::Service::Organization)
      end
    end

    context 'when the flag is on' do
      before { allow(AccreditedRepresentativePortal).to receive(:use_accredited_models?).and_return(true) }

      let!(:ct) { create(:accredited_organization, poa_code: '008', can_accept_digital_poa_requests: true) }

      it 'returns accredited organizations' do
        result = seeds.send(:fetch_organizations)

        expect(result[:ct]).to eq(ct)
        expect(result[:ct]).to be_a(AccreditedOrganization)
      end
    end
  end

  describe '#matching_reps_for' do
    context 'when the flag is on' do
      before { allow(AccreditedRepresentativePortal).to receive(:use_accredited_models?).and_return(true) }

      let(:organization) { create(:accredited_organization, poa_code: 'ABC') }
      let(:representative) { create(:accredited_individual, :representative) }
      let!(:accreditation) do
        create(:accreditation, accredited_individual: representative, accredited_organization: organization)
      end

      it 'returns the representatives accredited to the organization' do
        expect(seeds.send(:matching_reps_for, organization)).to include(representative)
      end
    end

    context 'when the flag is off' do
      before { allow(AccreditedRepresentativePortal).to receive(:use_accredited_models?).and_return(false) }

      let(:organization) { create(:organization, poa: 'ABC') }
      let!(:representative) { create(:representative, poa_codes: ['ABC']) }

      it 'returns the legacy representatives matching the poa code' do
        expect(seeds.send(:matching_reps_for, organization)).to include(representative)
      end
    end
  end

  describe '#create_poa_request' do
    let(:claimant) { create(:user_account) }

    context 'when the flag is on' do
      before { allow(AccreditedRepresentativePortal).to receive(:use_accredited_models?).and_return(true) }

      let(:organization) { create(:accredited_organization, poa_code: 'ABC') }
      let(:representative) { create(:accredited_individual, :representative, registration_number: '55555') }
      let!(:accreditation) do
        create(:accreditation, accredited_individual: representative, accredited_organization: organization)
      end

      it 'stores the shared FK identifiers and resolves the accredited records' do
        request = seeds.send(:create_poa_request, organization, representative, claimant, Time.current, false)

        expect(request.power_of_attorney_holder_poa_code).to eq('ABC')
        expect(request.accredited_individual_registration_number).to eq('55555')
        expect(request.accredited_organization).to eq(organization)
        expect(request.accredited_individual).to eq(representative)
      end
    end

    context 'when the flag is off' do
      before { allow(AccreditedRepresentativePortal).to receive(:use_accredited_models?).and_return(false) }

      let(:organization) { create(:organization, poa: 'ABC') }
      let(:representative) { create(:representative, representative_id: '66666', poa_codes: ['ABC']) }

      it 'stores the shared FK identifiers and resolves the legacy records' do
        request = seeds.send(:create_poa_request, organization, representative, claimant, Time.current, false)

        expect(request.power_of_attorney_holder_poa_code).to eq('ABC')
        expect(request.accredited_individual_registration_number).to eq('66666')
        expect(request.accredited_organization).to eq(organization)
        expect(request.accredited_individual).to eq(representative)
      end
    end
  end
end
