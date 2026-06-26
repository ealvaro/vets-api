# frozen_string_literal: true

require 'rails_helper'
require 'survivors_benefits/structured_data/V2025/section_06'

RSpec.describe SurvivorsBenefits::StructuredData::V2025::Section06 do
  describe '#merge_child_status_fields' do
    it 'sets multiple status checkboxes from a childStatus array' do
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new({})
      service.merge_child_status_fields(%w[BIOLOGICAL], 1)
      expect(service.fields).to include(
        'BIOLOGICAL_CHILD_1' => true,
        'ADOPTED_CHILD_1' => false,
        'STEPCHILD_1' => false
      )
    end

    it 'handles nil childStatus without raising' do
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new({})
      expect { service.merge_child_status_fields(nil, 1) }.not_to raise_error
      expect(service.fields).to include(
        'BIOLOGICAL_CHILD_1' => false,
        'ADOPTED_CHILD_1' => false,
        'STEPCHILD_1' => false
      )
    end
  end

  describe '#build_and_merge_child' do
    it 'reads childStatus array for school/disability/marriage/livesWith flags' do
      child = {
        'childFullName' => { 'first' => 'Emily', 'last' => 'Davis' },
        'childDateOfBirth' => '2000-01-01',
        'childSocialSecurityNumber' => '123-45-6789',
        'childPlaceOfBirth' => 'Anytown, WA',
        'childStatus' => %w[18-23_YEARS_OLD DOES_NOT_LIVE_WITH_SPOUSE],
        'childSupport' => 500.00
      }
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new({})
      service.build_and_merge_child(child, 1)
      expect(service.fields).to include(
        'NAME_OF_CHILD_1' => 'Emily Davis',
        'DATE_OF_BIRTH_CHILD_1' => '01/01/2000',
        'PLACE_OF_BIRTH_CHILD_1' => 'Anytown, WA',
        'CHILD_1_18_TO_23' => true,
        'CHILD_1_DISABLED' => false,
        'CHILD_1_PREV_MARRIED' => false,
        'CB_CHILD1_LIVE_WITH_OTHERS' => true,
        'AMNT_CONTRIBUTE_TO_CHILD_1' => '500.00'
      )
    end
  end

  describe '#child_place_of_birth' do
    it 'returns the string directly when childPlaceOfBirth is a string' do
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new({})
      child = { 'childPlaceOfBirth' => 'Seattle, WA' }
      expect(service.child_place_of_birth(child)).to eq('Seattle, WA')
    end

    it 'falls back to birthPlace hash when childPlaceOfBirth is absent' do
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new({})
      child = { 'birthPlace' => { 'city' => 'Anytown', 'state' => 'WA' } }
      expect(service.child_place_of_birth(child)).to eq('Anytown, WA')
    end
  end
end
