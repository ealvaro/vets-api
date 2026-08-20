# frozen_string_literal: true

require 'rails_helper'

RSpec.shared_examples 'search behavior' do |model_class|
  subject { described_class.new(params).perform }

  let(:id) { model_class.primary_key }
  let(:params) { { model_class:, type:, distance:, lat:, long:, sort:, name:, org_name: } }
  let(:type) { 'representative' }
  let(:distance) { 50 }
  let(:lat) { 38.9072 }
  let(:long) { -77.0369 }
  let(:sort) { 'distance_asc' }
  let(:name) { nil }
  let(:org_name) { nil }

  context 'when distance is not provided' do
    let(:distance) { nil }

    it 'includes all accredited individuals of the specified type' do
      expect(subject.pluck(id)).to contain_exactly(ind1.id, ind2.id, ind3.id, ind4.id, ind5.id, ind6.id)
    end
  end

  context 'when distance is provided' do
    it 'does not include accredited individuals located outside the max distance' do
      expect(subject.pluck(id)).to contain_exactly(ind1.id, ind2.id, ind3.id, ind4.id)
    end
  end

  context 'when sort is not provided' do
    let(:sort) { nil }

    it 'sorts results by distance_asc' do
      expect(subject.pluck(id)).to eq([ind1.id, ind2.id, ind3.id, ind4.id])
    end
  end

  context 'when sort is provided and distance_asc' do
    let(:sort) { 'distance_asc' }

    it 'sorts results by distance in ascending order' do
      expect(subject.pluck(id)).to eq([ind1.id, ind2.id, ind3.id, ind4.id])
    end
  end

  context 'when sort is provided and first_name_asc' do
    let(:sort) { 'first_name_asc' }

    it 'sorts results by first_name in ascending order' do
      expect(subject.pluck(id)).to eq([ind1.id, ind2.id, ind4.id, ind3.id])
    end
  end

  context 'when sort is provided and first_name_desc' do
    let(:sort) { 'first_name_desc' }

    it 'sorts results by first_name in descending order' do
      expect(subject.pluck(id)).to eq([ind3.id, ind4.id, ind2.id, ind1.id])
    end
  end

  context 'when sort is provided and last_name_asc' do
    let(:sort) { 'last_name_asc' }

    it 'sorts results by last_name in ascending order' do
      expect(subject.pluck(id)).to eq([ind1.id, ind4.id, ind2.id, ind3.id])
    end
  end

  context 'when sort is provided and last_name_desc' do
    let(:sort) { 'last_name_desc' }

    it 'sorts results by last_name in descending order' do
      expect(subject.pluck(id)).to eq([ind3.id, ind2.id, ind4.id, ind1.id])
    end
  end

  context 'when name is provided' do
    let(:name) { 'Bob Law' }

    it 'returns records where there is a fuzzy match on the name' do
      expect(subject.pluck(id)).to contain_exactly(ind1.id)
    end
  end

  context 'when org_name is provided' do
    let(:org_name) { 'Org Name' }

    context 'when type is representative' do
      it 'returns records where there is an exact match on the organization name' do
        expect(subject.pluck(id)).to eq([ind1.id, ind3.id])
      end
    end

    context 'when type is not representative' do
      let(:type) { 'attorney' }

      it 'ignores the org_name param' do
        expect(subject.pluck(id)).to contain_exactly(ind8.id)
      end
    end
  end

  context 'when type is attorney' do
    let(:type) { 'attorney' }

    it 'returns attorneys' do
      expect(subject.pluck(id)).to contain_exactly(ind8.id)
    end
  end

  context 'when type is claims_agent' do
    let(:type) { 'claims_agent' }

    it 'returns claims agents' do
      expect(subject.pluck(id)).to contain_exactly(ind9.id)
    end
  end
end

RSpec.describe RepresentationManagement::AccreditedIndividualSearch, type: :model do
  describe 'validations' do
    subject { described_class.new }

    it { expect(subject).to validate_inclusion_of(:distance).in_array(described_class::PERMITTED_MAX_DISTANCES) }
    it { expect(subject).to validate_presence_of(:lat) }
    it { expect(subject).to validate_numericality_of(:lat).is_greater_than_or_equal_to(-90) }
    it { expect(subject).to validate_numericality_of(:lat).is_less_than_or_equal_to(90) }
    it { expect(subject).to validate_presence_of(:long) }
    it { expect(subject).to validate_numericality_of(:long).is_greater_than_or_equal_to(-180) }
    it { expect(subject).to validate_numericality_of(:long).is_less_than_or_equal_to(180) }
    it { expect(subject).to validate_presence_of(:model_class) }
    it { expect(subject).to validate_inclusion_of(:model_class).in_array(described_class::PERMITTED_MODEL_CLASSES) }
    it { expect(subject).to validate_numericality_of(:page).only_integer }
    it { expect(subject).to validate_numericality_of(:per_page).only_integer }
    it { expect(subject).to validate_inclusion_of(:sort).in_array(described_class::PERMITTED_SORTS) }
    it { expect(subject).to validate_presence_of(:type) }
    it { expect(subject).to validate_inclusion_of(:type).in_array(described_class::PERMITTED_TYPES) }
  end

  describe '#perform' do
    context 'when the model_class is AccreditedIndividual' do
      let!(:ind1) do
        create(:accredited_individual, :with_organizations,
               org_name: 'Org Name', registration_number: '12300', individual_type: 'representative',
               long: -77.050552, lat: 38.820450, location: 'POINT(-77.050552 38.820450)',
               first_name: 'Bob', last_name: 'Law') # ~6 miles from Washington, D.C.
      end
      let!(:ind2) do
        create(:accredited_individual, :with_organizations,
               org_name: 'Another Org Name', registration_number: '23400', individual_type: 'representative',
               long: -77.436649, lat: 39.101481, location: 'POINT(-77.436649 39.101481)',
               first_name: 'Eliseo', last_name: 'Schroeder') # ~25 miles from Washington, D.C.
      end
      let!(:ind3) do
        create(:accredited_individual, :with_organizations,
               org_name: 'Org Name', registration_number: '34500', individual_type: 'representative',
               long: -76.609383, lat: 39.299236, location: 'POINT(-76.609383 39.299236)',
               first_name: 'Marci', last_name: 'Weissnat') # ~35 miles from Washington, D.C.
      end
      let!(:ind4) do
        create(:accredited_individual, :with_organizations,
               org_name: 'Another Org Name', registration_number: '45600', individual_type: 'representative',
               long: -77.466316, lat: 38.309875, location: 'POINT(-77.466316 38.309875)',
               first_name: 'Gerard', last_name: 'Ortiz') # ~47 miles from Washington, D.C.
      end
      let!(:ind5) do
        create(:accredited_individual, :with_organizations,
               org_name: 'Org Name', registration_number: '56700', individual_type: 'representative',
               long: -76.3483, lat: 39.5359, location: 'POINT(-76.3483 39.5359)',
               first_name: 'Adriane', last_name: 'Crona') # ~57 miles from Washington, D.C.
      end
      let!(:ind6) do
        create(:accredited_individual, :with_organizations,
               org_name: 'Org Name', registration_number: '67800', individual_type: 'representative',
               long: -76.3483, lat: 39.5359, location: 'POINT(-76.3483 39.5359)',
               first_name: 'Bob', last_name: 'Lawperson') # ~57 miles from Washington, D.C.
      end
      let!(:ind7) do
        create(:accredited_individual, :with_organizations,
               org_name: 'Org Name', registration_number: '78900', individual_type: 'representative',
               first_name: 'No', last_name: 'Location') # no location
      end
      let!(:ind8) do
        create(:accredited_individual,
               registration_number: '89100', individual_type: 'attorney',
               long: -77.050552, lat: 38.820450, location: 'POINT(-77.050552 38.820450)',
               first_name: 'Joe', last_name: 'Lawyer') # ~6 miles from Washington, D.C.
      end
      let!(:ind9) do
        create(:accredited_individual,
               registration_number: '90300', individual_type: 'claims_agent',
               long: -77.050552, lat: 38.820450, location: 'POINT(-77.050552 38.820450)',
               first_name: 'Jane', last_name: 'Agent') # ~6 miles from Washington, D.C.
      end

      include_examples 'search behavior', AccreditedIndividual
    end

    context 'when representatives have no active accreditation' do
      let(:params) do
        { model_class: AccreditedIndividual, type: 'representative', distance: 50,
          lat: 38.9072, long: -77.0369, sort: 'distance_asc', name: nil, org_name: nil }
      end
      let(:location) { 'POINT(-77.050552 38.820450)' } # ~6 miles from Washington, D.C.
      let!(:active_rep) do
        create(:accredited_individual, :with_organizations, registration_number: '11100',
                                                            individual_type: 'representative',
                                                            long: -77.050552, lat: 38.820450, location:)
      end
      let!(:rep_without_accreditation) do
        create(:accredited_individual, registration_number: '22200', individual_type: 'representative',
                                       long: -77.050552, lat: 38.820450, location:)
      end
      let!(:rep_with_deactivated_accreditation) do
        create(:accredited_individual, :with_organizations, registration_number: '33300',
                                                            individual_type: 'representative',
                                                            long: -77.050552, lat: 38.820450, location:).tap do |ind|
          ind.accreditations.update_all(deactivated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
        end
      end

      it 'excludes representatives that have no active accreditation' do
        results = described_class.new(params).perform.pluck(:id)

        expect(results).to include(active_rep.id)
        expect(results).not_to include(rep_without_accreditation.id, rep_with_deactivated_accreditation.id)
      end
    end

    context 'when filtering by org_name with a deactivated membership' do
      let(:params) do
        { model_class: AccreditedIndividual, type: 'representative', distance: 50,
          lat: 38.9072, long: -77.0369, sort: 'distance_asc', name: nil, org_name: 'Target Org' }
      end
      let(:location) { 'POINT(-77.050552 38.820450)' } # ~6 miles from Washington, D.C.
      let(:target_org) { create(:accredited_organization, name: 'Target Org') }
      let(:other_org) { create(:accredited_organization, name: 'Other Org') }
      let!(:active_member) do
        create(:accredited_individual, registration_number: '44400', individual_type: 'representative',
                                       long: -77.050552, lat: 38.820450, location:).tap do |ind|
          create(:accreditation, accredited_individual: ind, accredited_organization: target_org)
        end
      end
      let!(:deactivated_member) do
        create(:accredited_individual, registration_number: '55500', individual_type: 'representative',
                                       long: -77.050552, lat: 38.820450, location:).tap do |ind|
          create(:accreditation, accredited_individual: ind, accredited_organization: target_org,
                                 deactivated_at: Time.current)
          create(:accreditation, accredited_individual: ind, accredited_organization: other_org)
        end
      end

      it 'excludes representatives whose membership to that org has been deactivated' do
        results = described_class.new(params).perform.pluck(:id)

        expect(results).to contain_exactly(active_member.id)
      end
    end

    context 'when the model_class is Veteran::Service::Representative' do
      let!(:org1) { create(:veteran_organization, poa: 'A1Q', name: 'Org Name') }
      let!(:org2) { create(:veteran_organization, poa: 'H4L', name: 'Another Org Name') }
      let!(:ind1) do
        create(:veteran_representative, :vso,
               poa_codes: ['A1Q'], long: -77.050552, lat: 38.820450, location: 'POINT(-77.050552 38.820450)',
               first_name: 'Bob', last_name: 'Law') # ~6 miles from Washington, D.C.
      end
      let!(:ind2) do
        create(:veteran_representative, :vso,
               poa_codes: ['H4L'], long: -77.436649, lat: 39.101481, location: 'POINT(-77.436649 39.101481)',
               first_name: 'Eliseo', last_name: 'Schroeder') # ~25 miles from Washington, D.C.
      end
      let!(:ind3) do
        create(:veteran_representative, :vso,
               poa_codes: ['A1Q'], long: -76.609383, lat: 39.299236, location: 'POINT(-76.609383 39.299236)',
               first_name: 'Marci', last_name: 'Weissnat') # ~35 miles from Washington, D.C.
      end
      let!(:ind4) do
        create(:veteran_representative, :vso,
               poa_codes: ['H4L'], long: -77.466316, lat: 38.309875, location: 'POINT(-77.466316 38.309875)',
               first_name: 'Gerard', last_name: 'Ortiz') # ~47 miles from Washington, D.C.
      end
      let!(:ind5) do
        create(:veteran_representative, :vso,
               poa_codes: ['A1Q'], long: -76.3483, lat: 39.5359, location: 'POINT(-76.3483 39.5359)',
               first_name: 'Adriane', last_name: 'Crona') # ~57 miles from Washington, D.C.
      end
      let!(:ind6) do
        create(:veteran_representative, :vso,
               poa_codes: ['A1Q'], long: -76.3483, lat: 39.5359, location: 'POINT(-76.3483 39.5359)',
               first_name: 'Bob', last_name: 'Lawperson') # ~57 miles from Washington, D.C.
      end
      let!(:ind7) do
        create(:veteran_representative, :vso,
               poa_codes: ['A1Q'], first_name: 'No', last_name: 'Location') # no location
      end
      let!(:ind8) do
        create(:veteran_representative, # attorney
               poa_codes: ['Z9M'], long: -77.050552, lat: 38.820450, location: 'POINT(-77.050552 38.820450)',
               first_name: 'Joe', last_name: 'Lawyer') # ~6 miles from Washington, D.C.
      end
      let!(:ind9) do
        create(:veteran_representative, :claim_agents, # claims agent
               poa_codes: ['B2P'], long: -77.050552, lat: 38.820450, location: 'POINT(-77.050552 38.820450)',
               first_name: 'Jane', last_name: 'Agent') # ~6 miles from Washington, D.C.
      end

      include_examples 'search behavior', Veteran::Service::Representative
    end
  end
end
