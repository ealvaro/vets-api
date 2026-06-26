# frozen_string_literal: true

require 'rails_helper'
require 'survivors_benefits/structured_data/V2025/structured_data_service'

RSpec.describe SurvivorsBenefits::StructuredData::V2025::StructuredDataService do
  it 'includes the expected V2025 section modules' do
    expect(described_class.ancestors).to include(
      SurvivorsBenefits::StructuredData::V2025::Section01,
      SurvivorsBenefits::StructuredData::V2025::Section02,
      SurvivorsBenefits::StructuredData::V2025::Section03,
      SurvivorsBenefits::StructuredData::V2025::Section04,
      SurvivorsBenefits::StructuredData::V2025::Section05,
      SurvivorsBenefits::StructuredData::V2025::Section06,
      SurvivorsBenefits::StructuredData::V2025::Section07,
      SurvivorsBenefits::StructuredData::V2025::Section08,
      SurvivorsBenefits::StructuredData::V2025::Section09,
      SurvivorsBenefits::StructuredData::V2025::Section10,
      SurvivorsBenefits::StructuredData::V2025::Section11,
      SurvivorsBenefits::StructuredData::V2025::Section12,
      Mms::DataFormatting,
      Mms::Attachments
    )
  end

  describe '#initialize' do
    it 'initializes with form and a fields hash loaded from the V2025 FIELDS_PATH' do
      service = described_class.new({ 'key' => 'value' })
      expect(service.form).to eq({ 'key' => 'value' })
      expect(service.fields).to be_a(Hash)
    end
  end

  describe '#build_structured_data' do
    it 'calls every section builder without add_amounts_with_separation' do
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
      service.build_structured_data
    end
  end

  describe '#fill_veteran_ssn_reference_fields' do
    it 'populates 8 SSN reference fields (VETERAN_SSN_1 through VETERAN_SSN_8)' do
      service = described_class.new({ 'veteranSocialSecurityNumber' => '123-45-6789' })
      service.fill_veteran_ssn_reference_fields
      (1..8).each { |i| expect(service.fields["VETERAN_SSN_#{i}"]).to eq('123-45-6789') }
      expect(service.fields['VETERAN_SSN_9']).to be_nil
    end
  end
end
