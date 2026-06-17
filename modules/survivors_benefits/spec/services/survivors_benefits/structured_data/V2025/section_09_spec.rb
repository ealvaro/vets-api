# frozen_string_literal: true

require 'rails_helper'
require 'survivors_benefits/structured_data/V2025/section_09'

RSpec.describe SurvivorsBenefits::StructuredData::V2025::Section09 do
  describe '#build_section9' do
    it 'merges expected fields including ASSETS_OVER_25K and MORETHAN4_INCSOURCE' do
      form = {
        'incomeEntries' => [],
        'landMarketable' => true,
        'transferredAssets' => false,
        'homeOwnership' => true,
        'homeAcreageMoreThanTwo' => false,
        'moreThanFourIncomeSources' => true,
        'otherIncome' => false,
        'totalNetWorth' => false,
        'netWorthEstimation' => 50_000.25,
        'homeAcreageValue' => 100_000
      }
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new(form)
      service.build_section9
      expect(service.fields).to include(
        'MARKETABLE_LAND_2ACR_Y' => true,
        'MARKETABLE_LAND_2ACR_N' => false,
        'TRANSFER_ASSETS_LAST3Y_Y' => false,
        'TRANSFER_ASSETS_LAST3Y_N' => true,
        'OWN_PRIMARY_RESIDENCE_Y' => true,
        'OWN_PRIMARY_RESIDENCE_N' => false,
        'RESLOT_OVER_2ACR_Y' => false,
        'RESLOT_OVER_2ACR_N' => true,
        'MORETHAN4_INCSOURCE_Y' => true,
        'MORETHAN4_INCSOURCE_N' => false,
        'PREV_YEAR_OTHER_INCOME_YES' => false,
        'PREV_YEAR_OTHER_INCOME_NO' => true,
        'ASSETS_OVER_25K_Y' => false,
        'ASSETS_OVER_25K_N' => true,
        'AMNT_ESTIMATE_ASSETS' => '50,000.25',
        'AMNT_VALUE_OF_LOT' => '100,000.00'
      )
    end
  end

  describe '#merge_income_fields' do
    it 'merges expected fields including thousands/hundreds/cents breakdown' do
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
      expect(service.fields).to include(
        'CB_INC_RECIPIENT1_SP' => true,
        'CB_INC_RECIPIENT1_CHILD' => false,
        'NAME_OF_CHILD_INCOMETYPE1' => 'Jane Doe',
        'CB_INCOMETYPE1_SS' => true,
        'CB_INCOMETYPE1_PENSION' => false,
        'INCOME_PAYER_1' => 'SSA'
      )
    end
  end

  describe '#monthly_income_keys' do
    it 'returns keys with income_num inserted' do
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new({})
      keys = service.monthly_income_keys(3)
      expect(keys[:full]).to eq('MONTHLY_GROSS_3')
      expect(keys[:thousands]).to eq('MONTHLY_GROSS_3_THSNDS')
      expect(keys[:hundreds]).to eq('MONTHLY_GROSS_3_HNDRDS')
      expect(keys[:cents]).to eq('MONTHLY_GROSS_3_CENTS')
    end
  end
end
