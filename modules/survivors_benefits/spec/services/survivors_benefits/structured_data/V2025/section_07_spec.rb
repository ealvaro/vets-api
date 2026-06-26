# frozen_string_literal: true

require 'rails_helper'
require 'survivors_benefits/structured_data/V2025/section_07'

RSpec.describe SurvivorsBenefits::StructuredData::V2025::Section07 do
  describe '#build_section7' do
    it 'emits split NAME_MED_CENTER and LOC_MED_CENTER fields per treatment' do
      form = {
        'treatments' => [
          {
            'facilityInfo' => { 'vaMedicalCenterName' => 'VA Center 1', 'city' => 'Anytown', 'state' => 'WA' },
            'startDate' => '2020-01-01',
            'endDate' => '2020-01-10'
          },
          {
            'facilityInfo' => { 'vaMedicalCenterName' => 'VA Center 2', 'city' => 'Othertown', 'state' => 'OR' },
            'startDate' => '2021-02-01',
            'endDate' => '2021-02-15'
          }
        ]
      }
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new(form)
      service.build_section7
      expect(service.fields).to include(
        'NAME_MED_CENTER_1' => 'VA Center 1',
        'LOC_MED_CENTER_1' => 'Anytown, WA',
        'DATE_OF_TREATMENT_START1' => '01/01/2020',
        'DATE_OF_TREATMENT_END1' => '01/10/2020',
        'NAME_MED_CENTER_2' => 'VA Center 2',
        'LOC_MED_CENTER_2' => 'Othertown, OR'
      )
      expect(service.fields.keys).not_to include('NAME_LOC_MED_CENTER_1', 'NAME_LOC_MED_CENTER_2')
    end
  end

  describe '#treatment_location' do
    it 'joins city and state when both are present' do
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new({})
      treatment = { 'facilityInfo' => { 'city' => 'Portland', 'state' => 'OR' } }
      expect(service.treatment_location(treatment)).to eq('Portland, OR')
    end

    it 'returns nil when facilityInfo is absent' do
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new({})
      expect(service.treatment_location({})).to be_nil
    end
  end
end
