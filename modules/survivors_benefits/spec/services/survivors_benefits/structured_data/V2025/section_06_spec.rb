# frozen_string_literal: true

require 'rails_helper'
require 'survivors_benefits/structured_data/V2025/section_06'

RSpec.describe SurvivorsBenefits::StructuredData::V2025::Section06 do
  describe '#build_section6' do
    it 'calls merge_child_relationship_fields for each child' do
      form = {
        'childrenLiveTogetherButNotWithSpouse' => true,
        'veteransChildren' => [
          { 'relationship' => 'BIOLOGICAL' },
          { 'relationship' => 'ADOPTED' },
          { 'relationship' => 'STEPCHILD' }
        ]
      }
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new(form)
      expect(service).to receive(:merge_child_relationship_fields).with('BIOLOGICAL', 1)
      expect(service).to receive(:merge_child_relationship_fields).with('ADOPTED', 2)
      expect(service).to receive(:merge_child_relationship_fields).with('STEPCHILD', 3)
      service.build_section6
    end

    it 'handles nil children array' do
      form = { 'childrenLiveTogetherButNotWithSpouse' => true, 'veteransChildren' => nil }
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new(form)
      expect { service.build_section6 }.not_to raise_error
    end

    it 'merges expected Y/N and count fields' do
      form = { 'childrenLiveTogetherButNotWithSpouse' => true, 'veteranChildrenCount' => 3 }
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new(form)
      service.build_section6
      expect(service.fields).to include(
        'CHILD_DO_NOT_LIVE_WITH_CL_Y' => true,
        'CHILD_DO_NOT_LIVE_WITH_CL_N' => false,
        'NUMBER_OF_DEP_CHILD' => 3
      )
    end
  end

  describe '#merge_custodian_fields' do
    it 'merges custodian name and address fields' do
      form = {
        'custodianFullName' => { 'first' => 'Alice', 'middle' => 'B', 'last' => 'Johnson' },
        'custodianAddress' => {
          'street' => '789 B St',
          'street2' => 'Apt 4',
          'city' => 'Othertown',
          'state' => 'NY',
          'country' => 'US',
          'postalCode' => '54321-1234'
        }
      }
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new(form)
      service.merge_custodian_fields
      expect(service.fields).to include(
        'CUSTODIAN_CHILD1_NAME' => 'Alice B Johnson',
        'CUSTODIAN_CHILD1_FIRST_NAME' => 'Alice',
        'CUSTODIAN_CHILD1_MID_INT' => 'B',
        'CUSTODIAN_CHILD1_LAST_NAME' => 'Johnson',
        'CUSTODIAN_ADDRESS_LINE_1' => '789 B St',
        'CUSTODIAN_ADDRESS_CITY' => 'Othertown',
        'CUSTODIAN_ADDRESS_STATE' => 'NY',
        'CUSTODIAN_ADDRESS_ZIP' => '54321'
      )
    end
  end

  describe '#merge_child_relationship_fields' do
    it 'sets the matching relationship field to true and others to false' do
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new({})
      service.merge_child_relationship_fields('BIOLOGICAL', 1)
      service.merge_child_relationship_fields('ADOPTED', 2)
      service.merge_child_relationship_fields('STEPCHILD', 3)
      expect(service.fields).to include(
        'BIOLOGICAL_CHILD_1' => true,
        'ADOPTED_CHILD_1' => false,
        'STEPCHILD_1' => false,
        'BIOLOGICAL_CHILD_2' => false,
        'ADOPTED_CHILD_2' => true,
        'STEPCHILD_2' => false,
        'BIOLOGICAL_CHILD_3' => false,
        'ADOPTED_CHILD_3' => false,
        'STEPCHILD_3' => true
      )
    end
  end

  describe '#build_and_merge_child' do
    it 'builds and merges child fields including school/disability/marriage booleans' do
      child = {
        'childFullName' => { 'first' => 'Emily', 'middle' => 'C', 'last' => 'Davis' },
        'childDateOfBirth' => '2000-01-01',
        'childSocialSecurityNumber' => '123-45-6789',
        'birthPlace' => { 'city' => 'Anytown', 'state' => 'WA' },
        'inSchool' => true,
        'seriouslyDisabled' => false,
        'hasBeenMarried' => false,
        'livesWith' => true,
        'childSupport' => 500.00
      }
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new({})
      service.build_and_merge_child(child, 1)
      expect(service.fields).to include(
        'NAME_OF_CHILD_1' => 'Emily C Davis',
        'DATE_OF_BIRTH_CHILD_1' => '01/01/2000',
        'CHILD_1_SSN' => '123-45-6789',
        'PLACE_OF_BIRTH_CHILD_1' => 'Anytown, WA',
        'CHILD_1_18_TO_23' => true,
        'CHILD_1_DISABLED' => false,
        'CHILD_1_PREV_MARRIED' => false,
        'CB_CHILD1_LIVE_WITH_OTHERS' => true,
        'AMNT_CONTRIBUTE_TO_CHILD_1' => '500.00'
      )
    end
  end
end
