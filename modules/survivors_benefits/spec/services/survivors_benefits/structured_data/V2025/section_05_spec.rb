# frozen_string_literal: true

require 'rails_helper'
require 'survivors_benefits/structured_data/V2025/section_05'

RSpec.describe SurvivorsBenefits::StructuredData::V2025::Section05 do
  describe '#build_section5' do
    it 'calls merge_previous_marriage_fields for veteran and claimant' do
      form = {
        'veteranMarriages' => [{}],
        'claimantMarriages' => [{}],
        'veteranHasAdditionalMarriages' => true,
        'claimantHasAdditionalMarriages' => true
      }
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new(form)
      expect(service).to receive(:merge_previous_marriage_fields).twice
      service.build_section5
    end
  end

  describe '#individuals_permutations' do
    it 'returns correct permutations for VETERAN' do
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new({})
      expect(service.individuals_permutations('VETERAN')).to eq(%w[VET VET VETERAN])
    end

    it 'returns correct permutations for CLAIMANT' do
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new({})
      expect(service.individuals_permutations('CLAIMANT')).to eq(%w[CL CB_CL CLAIMANT])
    end
  end

  describe '#additional_marriages_boolean_fields' do
    it 'returns correct boolean fields for VET' do
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new({})
      expect(service.additional_marriages_boolean_fields('VET'))
        .to eq(%w[VET_ADDITIONAL_MARRIAGES_Y VET_ADDITIONAL_MARRIAGES_N])
    end

    it 'returns correct boolean fields for CL' do
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new({})
      expect(service.additional_marriages_boolean_fields('CL'))
        .to eq(%w[CL_ADDITIONAL_MARRIAGES_Y CL_ADDITIONAL_MARRIAGES_N])
    end
  end

  describe '#merge_spouse_name_fields' do
    it 'merges veteran\'s spouse name fields correctly' do
      name = { 'first' => 'Jane', 'middle' => 'A', 'last' => 'Smith' }
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new({})
      service.merge_spouse_name_fields(name, 'VETERAN', 1)
      expect(service.fields).to include(
        'VETERAN_MARRIAGE_1_TO' => 'Jane A Smith',
        'VETERAN_MARRIAGE_1_TO_FIRST_NAME' => 'Jane',
        'VETERAN_MARRIAGE_1_TO_MID_INT' => 'A',
        'VETERAN_MARRIAGE_1_TO_LAST_NAME' => 'Smith'
      )
    end
  end

  describe '#merge_previous_marriage_separation_type_fields' do
    it 'merges separation type fields with death as reason' do
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new({})
      service.merge_previous_marriage_separation_type_fields('VET', 'DEATH', 1)
      expect(service.fields).to include(
        'CB_VET_MARR1_ENDED_DEATH' => true,
        'CB_VET_MARR1_ENDED_DIVORCE' => false,
        'CB_VET_MARR1_ENDED_OTHER' => false
      )
    end

    it 'merges separation type fields with divorce as reason' do
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new({})
      service.merge_previous_marriage_separation_type_fields('VET', 'DIVORCE', 1)
      expect(service.fields).to include(
        'CB_VET_MARR1_ENDED_DEATH' => false,
        'CB_VET_MARR1_ENDED_DIVORCE' => true,
        'CB_VET_MARR1_ENDED_OTHER' => false
      )
    end
  end
end
