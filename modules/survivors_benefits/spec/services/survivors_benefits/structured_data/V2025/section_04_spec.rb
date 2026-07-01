# frozen_string_literal: true

require 'rails_helper'
require 'survivors_benefits/structured_data/V2025/section_04'

RSpec.describe SurvivorsBenefits::StructuredData::V2025::Section04 do
  describe '#build_section4' do
    it 'emits named checkboxes instead of a Y/N radio pair for separation reason' do
      form = {
        'separationDueToAssignedReasons' => true,
        'marriageType' => 'ceremonial'
      }
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new(form)
      service.build_section4
      expect(service.fields).to include(
        'SEPARATION_MEDICAL_FINANCIAL' => true,
        'MARITAL_DISCORD_OTHER' => false
      )
      expect(service.fields.keys).not_to include('MARITAL_DISCORD_SEPARATION_Y', 'MARITAL_DISCORD_SEPARATION_N')
    end

    it 'sets MARITAL_DISCORD_OTHER when separation is false' do
      form = { 'separationDueToAssignedReasons' => false, 'marriageType' => 'ceremonial' }
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new(form)
      service.build_section4
      expect(service.fields).to include(
        'SEPARATION_MEDICAL_FINANCIAL' => false,
        'MARITAL_DISCORD_OTHER' => true
      )
    end

    it 'merges all marital information fields' do
      form = {
        'validMarriage' => true,
        'childWithVeteran' => true,
        'pregnantWithVeteran' => true,
        'livedContinuouslyWithVeteran' => true,
        'separationDueToAssignedReasons' => true,
        'marriageType' => 'ceremonial',
        'marriageDates' => { 'from' => '2000-01-01', 'to' => '2010-01-01' },
        'placeOfMarriage' => 'Anytown, USA',
        'placeOfMarriageTermination' => 'Othertown, USA',
        'marriageTypeExplanation' => 'We had a ceremonial wedding.',
        'separationExplanation' => 'Financial issues.'
      }
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new(form)
      service.build_section4
      expect(service.fields).to include(
        'AWARE_OF_MARRIAGE_VALIDITY_YES' => true,
        'LIVE_WITH_VET_TILL_DEATH_YES' => true,
        'VET_CLAIMANT_MARRIAGE_1_DATE' => '01/01/2000',
        'MARITAL_DISCORD_SEPARATION_EXP' => 'Financial issues.'
      )
    end
  end

  describe '#merge_veteran_separation_fields when marriedToVeteranAtTimeOfDeath is nil' do
    it 'sets both MARRIED_WHILE_VET_DEATH flags to empty string' do
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new({})
      service.merge_veteran_separation_fields
      expect(service.fields).to include('MARRIED_WHILE_VET_DEATH_Y' => '', 'MARRIED_WHILE_VET_DEATH_N' => '')
    end
  end

  describe '#merge_claimant_remarriage_fields' do
    it 'reads remarried flag from the corrected field name remarriedAfterVeteranDeath' do
      form = { 'remarriedAfterVeteranDeath' => true, 'remarriageEndCause' => 'divorce' }
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new(form)
      service.merge_claimant_remarriage_fields
      expect(service.fields).to include(
        'REMARRIED_AFTER_VET_DEATH_YES' => true,
        'REMARRIED_AFTER_VET_DEATH_NO' => false
      )
    end

    it 'also accepts the legacy typo field name for backwards compatibility' do
      form = { 'remarriedAfterVeteralDeath' => true, 'remarriageEndCause' => 'death' }
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new(form)
      service.merge_claimant_remarriage_fields
      expect(service.fields['REMARRIED_AFTER_VET_DEATH_YES']).to be true
    end

    it 'sets both REMARRIED_AFTER_VET_DEATH flags to empty string when field is nil' do
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new({})
      service.merge_claimant_remarriage_fields
      expect(service.fields).to include('REMARRIED_AFTER_VET_DEATH_YES' => '', 'REMARRIED_AFTER_VET_DEATH_NO' => '')
    end
  end

  describe '#expand_and_merge_remarriage_end_cause' do
    it 'uses CB_REMARRIAGE_DID_NOT_END (not CB_MARRIAGE_DID_NOT_END)' do
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new({})
      service.expand_and_merge_remarriage_end_cause(true, 'didNotEnd')
      expect(service.fields).to include(
        'CB_REMARRIAGE_DID_NOT_END' => true,
        'CB_REMARRIAGE_END_BY_DEATH' => false,
        'CB_REMARRIAGE_END_BY_DIVORCE' => false,
        'CB_REMARRIAGE_END_BY_OTHER' => false
      )
      expect(service.fields.keys).not_to include('CB_MARRIAGE_DID_NOT_END')
    end

    it 'does not merge fields when has_remarried is false' do
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new({})
      service.expand_and_merge_remarriage_end_cause(false, 'death')
      expect(service.fields['CB_REMARRIAGE_END_BY_DEATH']).to be_nil
    end
  end
end
