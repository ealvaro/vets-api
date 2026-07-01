# frozen_string_literal: true

require 'rails_helper'
require 'survivors_benefits/structured_data/V2022/section_04'

RSpec.describe SurvivorsBenefits::StructuredData::V2022::Section04 do
  describe '#build_section4' do
    it 'merges marital information fields including Y/N separation radio pair' do
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
        'separationExplanation' => 'We separated due to financial issues.'
      }
      service = SurvivorsBenefits::StructuredData::V2022::StructuredDataService.new(form)
      service.build_section4
      expect(service.fields).to include(
        'AWARE_OF_MARRIAGE_VALIDITY_YES' => true,
        'AWARE_OF_MARRIAGE_VALIDITY_NO' => false,
        'CHILD_DURING_MARRIAGE_YES' => true,
        'CHILD_DURING_MARRIAGE_NO' => false,
        'EXPECTING_BIRTH_VET_CHILD_YES' => true,
        'EXPECTING_BIRTH_VET_CHILD_NO' => false,
        'LIVE_WITH_VET_TILL_DEATH_YES' => true,
        'LIVE_WITH_VET_TILL_DEATH_NO' => false,
        'MARITAL_DISCORD_SEPARATION_Y' => true,
        'MARITAL_DISCORD_SEPARATION_N' => false,
        'CB_CL_MARR_1_TYPE_CEREMONIAL' => true,
        'CB_CL_MARR_1_TYPE_OTHER' => false,
        'VET_CLAIMANT_MARRIAGE_1_DATE' => '01/01/2000',
        'VET_CLAIMANT_MARRIAGE_1_DATE_ENDED' => '01/01/2010',
        'VET_CLAIMANT_MARRIAGE_1_PLACE' => 'Anytown, USA',
        'VET_CLAIMANT_MARRIAGE_1_PLACE_ENDED' => 'Othertown, USA',
        'CL_MARR_1_TYPE_OTHEREXPLAIN' => 'We had a ceremonial wedding.',
        'MARITAL_DISCORD_SEPARATION_EXP' => 'We separated due to financial issues.'
      )
    end
  end

  describe '#marital_info_data' do
    it 'extracts marital information from the form' do
      form = {
        'pregnantWithVeteran' => true,
        'livedContinuouslyWithVeteran' => true,
        'separationDueToAssignedReasons' => true,
        'marriageType' => 'ceremonial'
      }
      service = SurvivorsBenefits::StructuredData::V2022::StructuredDataService.new(form)
      expect(service.marital_info_data).to eq([true, true, true, 'ceremonial'])
    end
  end

  describe '#merge_veteran_separation_fields' do
    describe 'when married to veteran at time of death' do
      it 'merges separation fields with death as reason' do
        form = { 'marriedToVeteranAtTimeOfDeath' => true }
        service = SurvivorsBenefits::StructuredData::V2022::StructuredDataService.new(form)
        service.merge_veteran_separation_fields
        expect(service.fields).to include(
          'MARRIED_WHILE_VET_DEATH_Y' => true,
          'MARRIED_WHILE_VET_DEATH_N' => false,
          'CB_MARR_TO_VET_ENDED_DEATH' => true,
          'CB_MARR_TO_VET_ENDED_DIVORCE' => false,
          'CB_MARR_TO_VET_ENDED_OTHER' => false
        )
      end
    end

    describe 'when not married to veteran at time of death' do
      it 'merges separation fields with divorce as reason' do
        form = { 'marriedToVeteranAtTimeOfDeath' => false, 'howMarriageEnded' => 'divorce' }
        service = SurvivorsBenefits::StructuredData::V2022::StructuredDataService.new(form)
        service.merge_veteran_separation_fields
        expect(service.fields).to include(
          'MARRIED_WHILE_VET_DEATH_Y' => false,
          'MARRIED_WHILE_VET_DEATH_N' => true,
          'CB_MARR_TO_VET_ENDED_DEATH' => false,
          'CB_MARR_TO_VET_ENDED_DIVORCE' => true,
          'CB_MARR_TO_VET_ENDED_OTHER' => false
        )
      end

      it 'merges separation fields with other as reason and includes explanation' do
        form = {
          'marriedToVeteranAtTimeOfDeath' => false,
          'howMarriageEnded' => 'other',
          'howMarriageEndedExplanation' => 'We separated due to financial issues.'
        }
        service = SurvivorsBenefits::StructuredData::V2022::StructuredDataService.new(form)
        service.merge_veteran_separation_fields
        expect(service.fields).to include(
          'CB_MARR_TO_VET_ENDED_OTHER' => true,
          'MARR_TO_VET_ENDED_OTHEREXPLAIN' => 'We separated due to financial issues.'
        )
      end
    end
  end

  describe '#merge_veteran_separation_fields when marriedToVeteranAtTimeOfDeath is nil' do
    it 'sets both MARRIED_WHILE_VET_DEATH flags to empty string' do
      service = SurvivorsBenefits::StructuredData::V2022::StructuredDataService.new({})
      service.merge_veteran_separation_fields
      expect(service.fields).to include('MARRIED_WHILE_VET_DEATH_Y' => '', 'MARRIED_WHILE_VET_DEATH_N' => '')
    end
  end

  describe '#merge_claimant_remarriage_fields' do
    it 'reads remarried flag from the V2022 typo field name' do
      form = { 'remarriedAfterVeteralDeath' => true, 'remarriageEndCause' => 'divorce' }
      service = SurvivorsBenefits::StructuredData::V2022::StructuredDataService.new(form)
      service.merge_claimant_remarriage_fields
      expect(service.fields).to include(
        'REMARRIED_AFTER_VET_DEATH_YES' => true,
        'REMARRIED_AFTER_VET_DEATH_NO' => false
      )
    end

    describe 'when remarriage end cause is divorce' do
      it 'merges remarriage fields' do
        form = {
          'remarriedAfterVeteralDeath' => true,
          'remarriageEndCause' => 'divorce',
          'claimantHasAdditionalMarriages' => true,
          'remarriageDates' => { 'from' => '2000-01-01', 'to' => '2010-01-01' }
        }
        service = SurvivorsBenefits::StructuredData::V2022::StructuredDataService.new(form)
        service.merge_claimant_remarriage_fields
        expect(service.fields).to include(
          'CLAIMANT_REMARRIAGE_1_DATE' => '01/01/2000',
          'CLAIMANT_REMARRIAGE_1_DATE_ENDED' => '01/01/2010',
          'CB_REMARRIAGE_END_BY_DEATH' => false,
          'CB_REMARRIAGE_END_BY_DIVORCE' => true,
          'CB_MARRIAGE_DID_NOT_END' => false,
          'CB_REMARRIAGE_END_BY_OTHER' => false
        )
      end
    end

    describe 'when remarriage did not end' do
      it 'sets CB_MARRIAGE_DID_NOT_END' do
        form = { 'remarriedAfterVeteralDeath' => true, 'remarriageEndCause' => 'didNotEnd' }
        service = SurvivorsBenefits::StructuredData::V2022::StructuredDataService.new(form)
        service.merge_claimant_remarriage_fields
        expect(service.fields).to include(
          'CB_MARRIAGE_DID_NOT_END' => true,
          'CB_REMARRIAGE_END_BY_DEATH' => false,
          'CB_REMARRIAGE_END_BY_DIVORCE' => false,
          'CB_REMARRIAGE_END_BY_OTHER' => false
        )
      end
    end

    it 'sets both REMARRIED_AFTER_VET_DEATH flags to empty string when field is nil' do
      service = SurvivorsBenefits::StructuredData::V2022::StructuredDataService.new({})
      service.merge_claimant_remarriage_fields
      expect(service.fields).to include('REMARRIED_AFTER_VET_DEATH_YES' => '', 'REMARRIED_AFTER_VET_DEATH_NO' => '')
    end
  end

  describe '#expand_and_merge_remarriage_end_cause' do
    it 'does not merge fields when has_remarried is false' do
      service = SurvivorsBenefits::StructuredData::V2022::StructuredDataService.new({})
      service.expand_and_merge_remarriage_end_cause(false, 'death')
      expect(service.fields).to include(
        'CB_REMARRIAGE_END_BY_DEATH' => nil,
        'CB_REMARRIAGE_END_BY_DIVORCE' => nil,
        'CB_MARRIAGE_DID_NOT_END' => nil,
        'CB_REMARRIAGE_END_BY_OTHER' => nil
      )
    end

    it 'merges remarriage end cause fields when has_remarried is true' do
      service = SurvivorsBenefits::StructuredData::V2022::StructuredDataService.new({})
      service.expand_and_merge_remarriage_end_cause(true, 'death')
      expect(service.fields).to include(
        'CB_REMARRIAGE_END_BY_DEATH' => true,
        'CB_REMARRIAGE_END_BY_DIVORCE' => false,
        'CB_MARRIAGE_DID_NOT_END' => false,
        'CB_REMARRIAGE_END_BY_OTHER' => false
      )
    end
  end
end
