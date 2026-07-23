# frozen_string_literal: true

require 'rails_helper'
require 'survivors_benefits/structured_data/V2022/section_12'

RSpec.describe SurvivorsBenefits::StructuredData::V2022::Section12 do
  describe '#build_section12' do
    it 'merges claim certification fields with a signed date' do
      form = {
        'claimantFullName' => { 'first' => 'John', 'last' => 'Doe' },
        'dateSigned' => '2024-01-01'
      }
      service = SurvivorsBenefits::StructuredData::V2022::StructuredDataService.new(form)
      service.build_section12
      expect(service.fields).to include(
        'CB_FURTHER_EVD_CLAIM_SUPPORT' => false,
        'CLAIM_TYPE_FULLY_DEVELOPED_CHK' => '',
        'CLAIMANT_SIGNATURE_X' => nil,
        'CLAIMANT_SIGNATURE' => 'John Doe',
        'DATE_OF_CLAIMANT_SIGNATURE' => '01/01/2024'
      )
    end

    it 'uses today\'s date when dateSigned is absent' do
      form = { 'claimantFullName' => { 'first' => 'John', 'last' => 'Doe' } }
      service = SurvivorsBenefits::StructuredData::V2022::StructuredDataService.new(form)
      service.build_section12
      expect(service.fields['DATE_OF_CLAIMANT_SIGNATURE']).to eq(Date.current.strftime('%m/%d/%Y'))
    end

    it 'routes a custodian signature to the alternate-signer line and blanks the claimant line' do
      form = {
        'claimantRelationship' => 'CUSTODIAN_FILING_FOR_CHILD_UNDER_18',
        'yourName' => { 'first' => 'Jane', 'last' => 'Custodian' },
        'claimantFullName' => { 'first' => 'Child', 'last' => 'Name' },
        'dateSigned' => '2024-01-01'
      }
      service = SurvivorsBenefits::StructuredData::V2022::StructuredDataService.new(form)
      service.build_section12
      expect(service.fields).to include(
        'CLAIMANT_SIGNATURE' => '',
        'DATE_OF_CLAIMANT_SIGNATURE' => '',
        'ALTERNATE_SIGNATURE' => 'Jane Custodian',
        'DateAltSigned' => '01/01/2024'
      )
    end

    it 'signs the claimant line with the signer (yourName) for a non-custodian relationship' do
      form = {
        'claimantRelationship' => 'SURVIVING_SPOUSE',
        'yourName' => { 'first' => 'Jane', 'last' => 'Doe' },
        'claimantFullName' => { 'first' => 'Jane', 'last' => 'Doe' },
        'dateSigned' => '2024-01-01'
      }
      service = SurvivorsBenefits::StructuredData::V2022::StructuredDataService.new(form)
      service.build_section12
      expect(service.fields).to include(
        'CLAIMANT_SIGNATURE' => 'Jane Doe',
        'DATE_OF_CLAIMANT_SIGNATURE' => '01/01/2024',
        'ALTERNATE_SIGNATURE' => '',
        'DateAltSigned' => ''
      )
    end

    it 'falls back to claimantFullName when yourName is absent' do
      form = {
        'claimantRelationship' => 'SURVIVING_SPOUSE',
        'claimantFullName' => { 'first' => 'John', 'last' => 'Doe' },
        'dateSigned' => '2024-01-01'
      }
      service = SurvivorsBenefits::StructuredData::V2022::StructuredDataService.new(form)
      service.build_section12
      expect(service.fields['CLAIMANT_SIGNATURE']).to eq('John Doe')
    end
  end
end
