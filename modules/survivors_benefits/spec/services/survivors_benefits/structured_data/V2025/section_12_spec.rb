# frozen_string_literal: true

require 'rails_helper'
require 'survivors_benefits/structured_data/V2025/section_12'

RSpec.describe SurvivorsBenefits::StructuredData::V2025::Section12 do
  describe '#build_section12' do
    it 'merges claim certification fields with a signed date' do
      form = {
        'claimantFullName' => { 'first' => 'John', 'last' => 'Doe' },
        'dateSigned' => '2024-01-01'
      }
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new(form)
      service.build_section12
      expect(service.fields).to include(
        'CB_FURTHER_EVD_CLAIM_SUPPORT' => false,
        'CLAIMANT_SIGNATURE' => 'John Doe',
        'DATE_OF_CLAIMANT_SIGNATURE' => '01/01/2024'
      )
      expect(service.fields.keys).not_to include('CLAIM_TYPE_FULLY_DEVELOPED_CHK')
    end

    it 'uses today\'s date when dateSigned is absent' do
      form = { 'claimantFullName' => { 'first' => 'John', 'last' => 'Doe' } }
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new(form)
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
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new(form)
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
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new(form)
      service.build_section12
      expect(service.fields).to include(
        'CLAIMANT_SIGNATURE' => 'Jane Doe',
        'DATE_OF_CLAIMANT_SIGNATURE' => '01/01/2024',
        'ALTERNATE_SIGNATURE' => '',
        'DateAltSigned' => ''
      )
    end

    it 'prefers filingCustodianFullName over the residual yourName key' do
      form = {
        'claimantRelationship' => 'CUSTODIAN_FILING_FOR_CHILD_UNDER_18',
        'filingCustodianFullName' => { 'first' => 'Jane', 'last' => 'Custodian' },
        'yourName' => { 'first' => 'Stale', 'last' => 'Value' },
        'claimantFullName' => { 'first' => 'Child', 'last' => 'Name' },
        'dateSigned' => '2024-01-01'
      }
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new(form)
      service.build_section12
      expect(service.fields['ALTERNATE_SIGNATURE']).to eq('Jane Custodian')
    end

    it 'never puts the child name on the alternate-signer line when yourName is pruned' do
      form = {
        'claimantRelationship' => 'CUSTODIAN_FILING_FOR_CHILD_UNDER_18',
        'filingCustodianFullName' => { 'first' => 'Jane', 'last' => 'Custodian' },
        'claimantFullName' => { 'first' => 'Child', 'last' => 'Name' },
        'dateSigned' => '2024-01-01'
      }
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new(form)
      service.build_section12
      expect(service.fields['ALTERNATE_SIGNATURE']).to eq('Jane Custodian')
    end

    it 'falls back to claimantFullName when yourName is absent' do
      form = {
        'claimantRelationship' => 'SURVIVING_SPOUSE',
        'claimantFullName' => { 'first' => 'John', 'last' => 'Doe' },
        'dateSigned' => '2024-01-01'
      }
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new(form)
      service.build_section12
      expect(service.fields['CLAIMANT_SIGNATURE']).to eq('John Doe')
    end
  end
end
