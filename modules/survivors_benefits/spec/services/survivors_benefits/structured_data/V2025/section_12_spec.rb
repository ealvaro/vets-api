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
  end
end
