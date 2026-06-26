# frozen_string_literal: true

require 'rails_helper'
require 'survivors_benefits/structured_data/V2025/section_09'

RSpec.describe SurvivorsBenefits::StructuredData::V2025::Section09 do
  describe '#build_section9' do
    it 'emits ASSETS_OVER_75K (not ASSETS_OVER_25K) for net worth threshold' do
      form = { 'incomeEntries' => [], 'totalNetWorth' => true }
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new(form)
      service.build_section9
      expect(service.fields).to include('ASSETS_OVER_75K_Y' => true, 'ASSETS_OVER_75K_N' => false)
      expect(service.fields.keys).not_to include('ASSETS_OVER_25K_Y', 'ASSETS_OVER_25K_N')
    end
  end

  describe '#merge_income_source_fields' do
    it 'maps NO_INCOME enum value' do
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new({})
      service.merge_income_source_fields('NO_INCOME')
      expect(service.fields).to include(
        'NO_INCOME' => true,
        '1_4_INCSOURCE_Y' => false,
        'MORETHAN4_INCSOURCE_Y' => false
      )
    end

    it 'maps ONE_TO_FOUR_SOURCES enum value' do
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new({})
      service.merge_income_source_fields('ONE_TO_FOUR_SOURCES')
      expect(service.fields).to include(
        'NO_INCOME' => false,
        '1_4_INCSOURCE_Y' => true,
        'MORETHAN4_INCSOURCE_Y' => false
      )
    end

    it 'maps MORE_THAN_FIVE_SOURCES enum value' do
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new({})
      service.merge_income_source_fields('MORE_THAN_FIVE_SOURCES')
      expect(service.fields).to include(
        'NO_INCOME' => false,
        '1_4_INCSOURCE_Y' => false,
        'MORETHAN4_INCSOURCE_Y' => true
      )
    end
  end

  describe '#merge_income_fields' do
    it 'emits a single MONTHLY_GROSS field (no thousands/hundreds/cents breakdown)' do
      form = {
        'incomeEntries' => [
          {
            'monthlyIncome' => 2_000,
            'recipient' => 'SURVIVING_SPOUSE',
            'recipientName' => 'Jane Doe',
            'incomeType' => 'SOCIAL_SECURITY',
            'incomePayer' => 'SSA'
          }
        ]
      }
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new(form)
      service.merge_income_fields(form['incomeEntries'])
      expect(service.fields['MONTHLY_GROSS_1']).to eq('2,000.00')
      expect(service.fields.keys).not_to include('MONTHLY_GROSS_1_THSNDS', 'MONTHLY_GROSS_1_HNDRDS')
    end

    it 'emits CUSTODIAN and CUSTODIAN_SPOUSE recipient fields' do
      form = {
        'incomeEntries' => [
          { 'monthlyIncome' => 100, 'recipient' => 'CUSTODIAN', 'incomeType' => 'OTHER' }
        ]
      }
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new(form)
      service.merge_income_fields(form['incomeEntries'])
      expect(service.fields).to include(
        'CB_INC_RECIPIENT1_CSTDN' => true,
        'CB_INC_RECIPIENT1_CSTDN_SP' => false,
        'CB_INC_RECIPIENT1_SP' => false
      )
    end
  end
end
