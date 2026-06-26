# frozen_string_literal: true

require 'rails_helper'
require 'survivors_benefits/structured_data/V2025/section_05'

RSpec.describe SurvivorsBenefits::StructuredData::V2025::Section05 do
  describe '#build_section5' do
    it 'emits CLMNT_SPSE_BFR_DTH_NLY_SPSE_Y/N when recognizedAsSpouse and hadPreviousMarriages are present' do
      form = {
        'recognizedAsSpouse' => true,
        'hadPreviousMarriages' => false,
        'veteranMarriages' => [],
        'spouseMarriages' => []
      }
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new(form)
      service.build_section5
      expect(service.fields).to include(
        'CLMNT_SPSE_BFR_DTH_NLY_SPSE_Y' => true,
        'CLMNT_SPSE_BFR_DTH_NLY_SPSE_N' => false
      )
    end

    it 'sets CLMNT_SPSE_BFR_DTH_NLY_SPSE_N when claimant was not recognized as only spouse' do
      form = {
        'recognizedAsSpouse' => true,
        'hadPreviousMarriages' => true,
        'veteranMarriages' => [],
        'spouseMarriages' => []
      }
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new(form)
      service.build_section5
      expect(service.fields).to include(
        'CLMNT_SPSE_BFR_DTH_NLY_SPSE_Y' => false,
        'CLMNT_SPSE_BFR_DTH_NLY_SPSE_N' => true
      )
    end

    it 'reads claimant marriages from spouseMarriages key' do
      form = {
        'spouseMarriages' => [
          { 'spouseFullName' => { 'first' => 'John', 'last' => 'Doe' }, 'reasonForSeparation' => 'DEATH' }
        ],
        'spouseHasAdditionalMarriages' => false,
        'veteranMarriages' => []
      }
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new(form)
      service.build_section5
      expect(service.fields['CLAIMANT_MARRIAGE_1_TO']).to eq('John Doe')
    end
  end

  describe '#recognized_no_previous_value' do
    it 'returns true when recognized as spouse and no previous marriages' do
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new(
        'recognizedAsSpouse' => true, 'hadPreviousMarriages' => false
      )
      expect(service.recognized_no_previous_value).to be true
    end

    it 'returns false when recognized but had previous marriages' do
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new(
        'recognizedAsSpouse' => true, 'hadPreviousMarriages' => true
      )
      expect(service.recognized_no_previous_value).to be false
    end

    it 'returns nil when either value is absent' do
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new({})
      expect(service.recognized_no_previous_value).to be_nil
    end
  end
end
