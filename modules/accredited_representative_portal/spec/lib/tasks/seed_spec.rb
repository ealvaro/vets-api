# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe 'AccreditedRepresentativePortal::Seed' do
  before(:all) do
    load Rails.root.join('modules', 'accredited_representative_portal', 'lib', 'tasks', 'seed.rake').to_s
  end

  let(:seed) { AccreditedRepresentativePortal::Seed }
  let(:records) { AccreditedRepresentativePortal::Seed::Records }

  describe '.build_accreditations' do
    it 'pairs each representative registration number with each of its poa codes' do
      result = seed.send(:build_accreditations)

      expected_size = records::REPRESENTATIVES.sum { |rep| rep[:poa_codes].size }
      expect(result.size).to eq(expected_size)
      expect(result).to all(include(:accredited_individual_id, :accredited_organization_id))
    end
  end

  describe '.insert_legacy_vso_records' do
    it 'creates only legacy Veteran::Service records' do
      expect { seed.send(:insert_legacy_vso_records) }
        .to change(Veteran::Service::Organization, :count).by(records::ORGANIZATIONS.size)
        .and change(Veteran::Service::Representative, :count).by(records::REPRESENTATIVES.size)

      expect(AccreditedOrganization.count).to eq(0)
      expect(AccreditedIndividual.count).to eq(0)
      expect(Accreditation.count).to eq(0)
    end
  end

  describe '.insert_accredited_vso_records' do
    before { seed.send(:insert_accredited_vso_records) }

    it 'creates an accredited organization per seeded organization' do
      expect(AccreditedOrganization.count).to eq(records::ORGANIZATIONS.size)
    end

    it 'seeds both digital and non-digital organizations' do
      expect(AccreditedOrganization.where(can_accept_digital_poa_requests: true)).to exist
      expect(AccreditedOrganization.where(can_accept_digital_poa_requests: false)).to exist
    end

    it 'creates a representative individual per seeded representative' do
      expect(AccreditedIndividual.representatives.count).to eq(records::REPRESENTATIVES.size)
    end

    it 'creates accreditations with a mix of acceptance modes' do
      expected_size = records::REPRESENTATIVES.sum { |rep| rep[:poa_codes].size }

      expect(Accreditation.count).to eq(expected_size)
      expect(Accreditation.where(acceptance_mode: 'any_request')).to exist
      expect(Accreditation.where(acceptance_mode: 'self_only')).to exist
      expect(Accreditation.where(acceptance_mode: 'no_acceptance')).not_to exist
    end

    it 'does not create legacy VSO records' do
      expect(Veteran::Service::Organization.count).to eq(0)
      expect(Veteran::Service::Representative.count).to eq(0)
    end
  end

  describe '.find_accredited_individual' do
    let(:registration_number) { records::REPRESENTATIVES.first[:representative_id] }

    context 'when the flag is off' do
      before do
        allow(AccreditedRepresentativePortal).to receive(:use_accredited_models?).and_return(false)
        create(:representative, representative_id: registration_number)
      end

      it 'returns the legacy representative' do
        expect(seed.send(:find_accredited_individual, registration_number))
          .to be_a(Veteran::Service::Representative)
      end
    end

    context 'when the flag is on' do
      before do
        allow(AccreditedRepresentativePortal).to receive(:use_accredited_models?).and_return(true)
        create(:accredited_individual, :representative, registration_number:)
      end

      it 'returns the accredited individual' do
        expect(seed.send(:find_accredited_individual, registration_number))
          .to be_a(AccreditedIndividual)
      end
    end
  end
end
