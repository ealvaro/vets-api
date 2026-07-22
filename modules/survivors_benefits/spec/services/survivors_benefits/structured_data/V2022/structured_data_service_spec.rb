# frozen_string_literal: true

require 'rails_helper'
require 'survivors_benefits/structured_data/V2022/structured_data_service'

RSpec.describe SurvivorsBenefits::StructuredData::V2022::StructuredDataService do
  it 'includes the expected V2022 section modules' do
    expect(described_class.ancestors).to include(
      SurvivorsBenefits::StructuredData::V2022::Section01,
      SurvivorsBenefits::StructuredData::V2022::Section02,
      SurvivorsBenefits::StructuredData::V2022::Section03,
      SurvivorsBenefits::StructuredData::V2022::Section04,
      SurvivorsBenefits::StructuredData::V2022::Section05,
      SurvivorsBenefits::StructuredData::V2022::Section06,
      SurvivorsBenefits::StructuredData::V2022::Section07,
      SurvivorsBenefits::StructuredData::V2022::Section08,
      SurvivorsBenefits::StructuredData::V2022::Section09,
      SurvivorsBenefits::StructuredData::V2022::Section10,
      SurvivorsBenefits::StructuredData::V2022::Section11,
      SurvivorsBenefits::StructuredData::V2022::Section12,
      Mms::DataFormatting
    )
  end

  describe '#initialize' do
    it 'initializes with form and a fields hash loaded from the V2022 FIELDS_PATH' do
      form = { 'key' => 'value' }
      service = described_class.new(form)
      expect(service.form).to eq(form)
      expect(service.fields).to be_a(Hash)
    end
  end

  describe '#build_structured_data' do
    it 'calls every section builder and post-processing steps' do
      service = described_class.new({})
      expect(service).to receive(:build_section1)
      expect(service).to receive(:build_section2)
      expect(service).to receive(:build_section3)
      expect(service).to receive(:build_section4)
      expect(service).to receive(:build_section5)
      expect(service).to receive(:build_section6)
      expect(service).to receive(:build_section7)
      expect(service).to receive(:build_section8)
      expect(service).to receive(:build_section9)
      expect(service).to receive(:build_section10)
      expect(service).to receive(:build_section11).with(nil)
      expect(service).to receive(:build_section12)
      expect(service).to receive(:fill_veteran_ssn_reference_fields)
      expect(service).to receive(:add_amounts_with_separation)
      service.build_structured_data
    end
  end

  describe '#fill_veteran_ssn_reference_fields' do
    it 'populates 9 SSN reference fields (VETERAN_SSN_1 through VETERAN_SSN_9)' do
      form = { 'veteranSocialSecurityNumber' => '123-45-6789' }
      service = described_class.new(form)
      service.fill_veteran_ssn_reference_fields
      (1..9).each do |i|
        expect(service.fields["VETERAN_SSN_#{i}"]).to eq('123-45-6789')
      end
    end
  end

  describe '#merge_name_fields' do
    it 'merges full, first, middle initial, and last name fields' do
      service = described_class.new({})
      service.merge_name_fields({ 'first' => 'John', 'middle' => 'A', 'last' => 'Doe', 'suffix' => 'Jr.' }, 'VETERAN')
      expect(service.fields).to include(
        'VETERAN_NAME' => 'John A Doe Jr.',
        'VETERAN_FIRST_NAME' => 'John',
        'VETERAN_MIDDLE_INITIAL' => 'A',
        'VETERAN_LAST_NAME' => 'Doe'
      )
    end

    it 'does not merge fields when name is nil' do
      service = described_class.new({})
      service.merge_name_fields(nil, 'VETERAN')
      expect(service.fields['VETERAN_NAME']).to be_nil
    end
  end
end
