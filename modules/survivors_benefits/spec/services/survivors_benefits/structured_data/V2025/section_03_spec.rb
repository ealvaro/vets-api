# frozen_string_literal: true

require 'rails_helper'
require 'survivors_benefits/structured_data/V2025/section_03'

RSpec.describe SurvivorsBenefits::StructuredData::V2025::Section03 do
  describe '#build_section3' do
    it 'merges split reserve unit name and address fields' do
      form = {
        'activeServiceDateRange' => { 'from' => '1965-01-01', 'to' => '1975-01-01' },
        'placeOfSeparation' => 'Anytown, CA',
        'nationalGuardActivated' => true,
        'nationalGuardActivationDate' => '1965-01-01',
        'unitName' => 'Unit 123',
        'unitAddress' => '456 Military Rd, Anytown, USA',
        'unitPhone' => '555-987-6543',
        'pow' => true,
        'powDateRange' => { 'from' => '1967-01-01', 'to' => '1968-01-01' }
      }
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new(form)
      service.build_section3
      expect(service.fields).to include(
        'DATE_ENTERED_TO_SERVICE' => '01/01/1965',
        'DATE_SEPARATED_FROM_SERVICE' => '01/01/1975',
        'PLACE_SEPARATED_FROM_SERVICE_1' => 'Anytown, CA',
        'ACTIVATED_TO_FED_DUTY_YES' => true,
        'ACTIVATED_TO_FED_DUTY_NO' => false,
        'DATE_OF_ACTIVATION' => '01/01/1965',
        'NAME_RESERVE_UNIT' => 'Unit 123',
        'ADDRESS_RESERVE_UNIT' => '456 Military Rd, Anytown, USA',
        'RESERVE_PHONE_NUMBER' => '555-987-6543',
        'POW_YES' => true,
        'POW_NO' => false,
        'DATE_OF_CONFINEMENT_START' => '01/01/1967',
        'DATE_OF_CONFINEMENT_END' => '01/01/1968'
      )
    end

    it 'does not emit NAME_ADDRESS_RESERVE_UNIT combined field' do
      form = { 'unitName' => 'Unit 1', 'unitAddress' => '123 St' }
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new(form)
      service.build_section3
      expect(service.fields.keys).not_to include('NAME_ADDRESS_RESERVE_UNIT')
    end
  end

  describe '#merge_vet_aliases' do
    it 'merges veteran alias fields from flat hash using middle initial' do
      aliases = [
        { 'first' => 'Johnny', 'middle' => 'Quincy', 'last' => 'Doe' },
        { 'first' => 'J', 'last' => 'Doe' }
      ]
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new({})
      service.merge_vet_aliases(aliases)
      expect(service.fields).to include(
        'VET_NAME_OTHER_Y' => true,
        'VET_NAME_OTHER_N' => false,
        'VET_NAME_OTHER_1' => 'Johnny Q Doe',
        'VET_NAME_OTHER_2' => 'J Doe'
      )
    end

    it 'merges veteran alias fields from otherServiceName nested shape' do
      aliases = [
        { 'otherServiceName' => { 'first' => 'Johnny', 'middle' => 'Quincy', 'last' => 'Doe', 'suffix' => 'Jr.' } },
        { 'otherServiceName' => { 'first' => 'J', 'last' => 'Doe' } }
      ]
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new({})
      service.merge_vet_aliases(aliases)
      expect(service.fields).to include(
        'VET_NAME_OTHER_Y' => true,
        'VET_NAME_OTHER_N' => false,
        'VET_NAME_OTHER_1' => 'Johnny Q Doe Jr.',
        'VET_NAME_OTHER_2' => 'J Doe'
      )
    end

    it 'sets both VET_NAME_OTHER flags to empty string when aliases are nil (question not answered)' do
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new({})
      service.merge_vet_aliases(nil)
      expect(service.fields).to include('VET_NAME_OTHER_Y' => '', 'VET_NAME_OTHER_N' => '')
    end
  end

  describe '#merge_service_branch_fields' do
    it 'merges all service branch fields correctly' do
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new({ 'serviceBranch' => 'navy' })
      service.merge_service_branch_fields('navy')
      expect(service.fields).to include(
        'BRANCH_OF_SERVICE_ARMY' => false,
        'BRANCH_OF_SERVICE_NAVY' => true,
        'BRANCH_OF_SERVICE_AIR-FORCE' => false,
        'BRANCH_OF_SERVICE_SPACE' => false
      )
    end
  end
end
