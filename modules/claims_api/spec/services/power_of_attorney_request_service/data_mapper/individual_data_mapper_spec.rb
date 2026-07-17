# frozen_string_literal: true

require 'rails_helper'
require_relative '../../../poa_auto_establishment_spec_helper'

describe ClaimsApi::PowerOfAttorneyRequestService::DataMapper::IndividualDataMapper do
  subject { described_class.new(data: individual_gathered_data) }

  include_context 'shared POA auto establishment data'

  it 'maps the data correctly' do
    allow_any_instance_of(described_class).to receive(:representative_type).and_return('ATTORNEY')

    res = subject.map_data

    expect(res).to eq(individual_mapped_form_data)
  end

  it 'raises an error if no rep is found' do
    expect do
      subject.send(:validate_representative!, nil, '083')
    end.to raise_error(Common::Exceptions::ResourceNotFound)
  end

  context 'when gathered data includes birth_date in claimant' do
    subject { described_class.new(data: gathered_data_with_birth_date) }

    let(:gathered_data_with_birth_date) do
      individual_gathered_data.merge(
        'claimant' => individual_gathered_data['claimant'].merge('birth_date' => '1990-01-15')
      )
    end

    it 'includes dateOfBirth in mapped claimant data' do
      allow_any_instance_of(described_class).to receive(:representative_type).and_return('ATTORNEY')

      res = subject.map_data

      expect(res.dig('data', 'attributes', 'claimant', 'dateOfBirth')).to eq('1990-01-15')
    end
  end

  context 'when gathered data does not include birth_date in claimant' do
    it 'does not include dateOfBirth in mapped claimant data' do
      allow_any_instance_of(described_class).to receive(:representative_type).and_return('ATTORNEY')

      res = subject.map_data

      expect(res.dig('data', 'attributes', 'claimant')).not_to have_key('dateOfBirth')
    end
  end

  context 'when gathered data includes form_attributes with consent disclosure fields' do
    subject { described_class.new(data: gathered_data_with_form_attrs) }

    let(:gathered_data_with_form_attrs) do
      individual_gathered_data.merge(
        'form_attributes' => {
          'consent_disclosure_affiliated' => true,
          'consent_disclosure_individuals' => true,
          'firm_or_org_name' => 'Smith & Associates',
          'individual_names' => ['jane', 'janey lee']
        }
      )
    end

    it 'includes consentDisclosureAffiliated in mapped data' do
      allow_any_instance_of(described_class).to receive(:representative_type).and_return('ATTORNEY')

      res = subject.map_data

      expect(res.dig('data', 'attributes', 'consentDisclosureAffiliated')).to be(true)
    end

    it 'includes consentDisclosureIndividuals in mapped data' do
      allow_any_instance_of(described_class).to receive(:representative_type).and_return('ATTORNEY')

      res = subject.map_data

      expect(res.dig('data', 'attributes', 'consentDisclosureIndividuals')).to be(true)
    end

    it 'includes firmOrOrgName in mapped data' do
      allow_any_instance_of(described_class).to receive(:representative_type).and_return('ATTORNEY')

      res = subject.map_data

      expect(res.dig('data', 'attributes', 'firmOrOrgName')).to eq('Smith & Associates')
    end

    it 'includes individualNames in mapped data' do
      allow_any_instance_of(described_class).to receive(:representative_type).and_return('ATTORNEY')

      res = subject.map_data

      expect(res.dig('data', 'attributes', 'individualNames')).to eq(['jane', 'janey lee'])
    end

    it 'omits nil form attributes and preserves false values' do
      partial_form_attrs_data = individual_gathered_data.merge(
        'form_attributes' => {
          'consent_disclosure_affiliated' => false,
          'consent_disclosure_individuals' => nil,
          'firm_or_org_name' => nil,
          'individual_names' => ['jane']
        }
      )
      service = described_class.new(data: partial_form_attrs_data)
      allow_any_instance_of(described_class).to receive(:representative_type).and_return('ATTORNEY')

      res = service.map_data
      attrs = res.dig('data', 'attributes')

      expect(attrs['consentDisclosureAffiliated']).to be(false)
      expect(attrs['individualNames']).to eq(['jane'])
      expect(attrs).not_to have_key('consentDisclosureIndividuals')
      expect(attrs).not_to have_key('firmOrOrgName')
    end
  end

  context 'when gathered data does not include form_attributes' do
    it 'does not include consentDisclosureAffiliated in mapped data' do
      allow_any_instance_of(described_class).to receive(:representative_type).and_return('ATTORNEY')

      res = subject.map_data

      expect(res.dig('data', 'attributes')).not_to have_key('consentDisclosureAffiliated')
    end

    it 'does not include consentDisclosureIndividuals in mapped data' do
      allow_any_instance_of(described_class).to receive(:representative_type).and_return('ATTORNEY')

      res = subject.map_data

      expect(res.dig('data', 'attributes')).not_to have_key('consentDisclosureIndividuals')
    end

    it 'does not include firmOrOrgName in mapped data' do
      allow_any_instance_of(described_class).to receive(:representative_type).and_return('ATTORNEY')

      res = subject.map_data

      expect(res.dig('data', 'attributes')).not_to have_key('firmOrOrgName')
    end

    it 'does not include individualNames in mapped data' do
      allow_any_instance_of(described_class).to receive(:representative_type).and_return('ATTORNEY')

      res = subject.map_data

      expect(res.dig('data', 'attributes')).not_to have_key('individualNames')
    end
  end
end
