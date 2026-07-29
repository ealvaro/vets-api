# frozen_string_literal: true

require 'rails_helper'
require 'dgi/claimant_info_helpers'

class TestClass
  include ClaimantInfoHelpers
end

RSpec.describe ClaimantInfoHelpers do
  let(:test_instance) { TestClass.new }

  describe '#map_non33' do
    context 'debugging path to delimiting_date' do
      let(:non33_data) do
        [{
          'benefit_type' => 'CH1606',
          'entitlement_result' => {
            'id' => 3_000_000_010_001_390,
            'orig_entitled_days' => 1080.00000,
            'days_used' => 151.00000,
            'days_remaining' => 929.00000
          },
          'eligibility_result' => {
            'id' => 2_000_000_002_004_792,
            'eligibility_period' => {
              'id' => 2_000_000_002_004_792,
              'eligibility_date' => '2025-07-24',
              'delimiting_date' => '2026-07-10'
            }
          }
        }]
      end

      it 'shows each step of the path' do
        non33_data.first

        result = test_instance.map_non33(non33_data)

        expect(result.first[:benefit_end_date]).to eq('2026-07-10')
      end
    end

    context 'with CH1606 benefit data matching actual API payload' do
      let(:non33_data) do
        [{
          'benefit_type' => 'CH1606',
          'entitlement_result' => {
            'id' => 3_000_000_010_001_390,
            'orig_entitled_days' => 1080.00000,
            'days_used' => 151.00000,
            'days_remaining' => 929.00000,
            'vt2_entitlement_charged_days' => nil,
            'vt2_exhaustion_date' => nil,
            'exhaustion_date' => nil,
            'is_current' => true,
            'benefit_type' => 'CH1606'
          },
          'eligibility_result' => {
            'id' => 2_000_000_002_004_792,
            'total_service_period' => nil,
            'tot_aggregat_qualifying_days' => nil,
            'tot_aggregate_training_days' => nil,
            'tot_aggregate_exclusion_days' => nil,
            'active_duty' => false,
            'served_after09102001' => false,
            'over90_and_honorable' => false,
            'over30_consecutive_disabled' => false,
            'veteran_is_eligible' => true,
            'purple_heart_benefit_date' => nil,
            'stem_eligibility_period' => nil,
            'eligibility_period' => {
              'id' => 2_000_000_002_004_792,
              'eligibility_date' => '2025-07-24',
              'delimiting_date' => '2026-07-10'
            },
            'is_current' => true,
            'benefit_type' => 'CH1606',
            'benefit_status_code' => 'PEND',
            'self_benefit_established' => true,
            'percentage_benefit' => nil,
            'bgs_add_benefit_failed' => false,
            'source_claimant_id' => nil
          }
        }]
      end

      it 'extracts the delimiting_date from eligibility_period' do
        result = test_instance.map_non33(non33_data)

        expect(result).to be_an(Array)
        expect(result.length).to eq(1)

        benefit = result.first

        expect(benefit[:benefit_type]).to eq('CH1606')
        expect(benefit[:benefit_end_date]).to eq('2026-07-10')
      end
    end
  end

  describe '#ch33' do
    context 'when vettec_days_used is present' do
      let(:ch33_data) do
        {
          'benefit_or_source_type' => 'CH33',
          'ch33_original_entitled_days' => 1080.0,
          'ch33_days_used' => 120.0,
          'vettec_days_used' => 30.0,
          'ch33_days_remaining' => 930.0,
          'percentage_benefit' => 100,
          'delimiting_date' => '2030-01-15'
        }
      end

      it 'sums ch33_days_used and vettec_days_used for amount_used' do
        result = test_instance.ch33(ch33_data)

        expect(result[:benefit_type]).to eq('CH33')
        expect(result[:amount_received]).to eq({ months: 36, days: 0 })
        # 120 + 30 = 150 days = 5 months
        expect(result[:amount_used]).to eq({ months: 5, days: 0 })
        expect(result[:amount_left]).to eq({ months: 31, days: 0 })
        expect(result[:eligibility_percentage]).to eq(100)
        expect(result[:benefit_end_date]).to eq('2030-01-15')
      end
    end

    context 'when vettec_days_used is nil' do
      let(:ch33_data) do
        {
          'benefit_or_source_type' => 'CH33',
          'ch33_original_entitled_days' => 1080.0,
          'ch33_days_used' => 120.0,
          'vettec_days_used' => nil,
          'ch33_days_remaining' => 960.0,
          'percentage_benefit' => 100,
          'delimiting_date' => '2030-01-15'
        }
      end

      it 'uses only ch33_days_used for amount_used' do
        result = test_instance.ch33(ch33_data)

        # 120 days = 4 months
        expect(result[:amount_used]).to eq({ months: 4, days: 0 })
      end
    end

    context 'when vettec_days_used is missing from payload' do
      let(:ch33_data) do
        {
          'benefit_or_source_type' => 'CH33',
          'ch33_original_entitled_days' => 1080.0,
          'ch33_days_used' => 90.0,
          'ch33_days_remaining' => 990.0,
          'percentage_benefit' => 100,
          'delimiting_date' => '2030-01-15'
        }
      end

      it 'uses only ch33_days_used for amount_used' do
        result = test_instance.ch33(ch33_data)

        # 90 days = 3 months
        expect(result[:amount_used]).to eq({ months: 3, days: 0 })
      end
    end
  end

  describe '#get_benefits' do
    context 'with real API payload structure' do
      let(:non33_eligibilities) do
        [{
          'benefit_type' => 'CH1606',
          'entitlement_result' => {
            'id' => 3_000_000_010_001_390,
            'orig_entitled_days' => 1080.00000,
            'days_used' => 151.00000,
            'days_remaining' => 929.00000
          },
          'eligibility_result' => {
            'eligibility_period' => {
              'eligibility_date' => '2025-07-24',
              'delimiting_date' => '2026-07-10'
            }
          }
        }]
      end

      let(:latest_ch33_eligibility) { nil }

      it 'includes benefit_end_date for non-CH33 benefits' do
        result = test_instance.get_benefits(['CH1606'], non33_eligibilities, latest_ch33_eligibility)

        expect(result.first[:benefit_end_date]).to eq('2026-07-10')
      end
    end

    context 'with CH33 benefit including VetTec usage' do
      let(:non33_eligibilities) { [] }
      let(:latest_ch33_eligibility) do
        {
          'benefit_or_source_type' => 'CH33',
          'ch33_original_entitled_days' => 1080.0,
          'ch33_days_used' => 200.0,
          'vettec_days_used' => 50.0,
          'ch33_days_remaining' => 830.0,
          'percentage_benefit' => 100,
          'delimiting_date' => '2030-01-15'
        }
      end

      it 'combines CH33 and VetTec days in amount_used' do
        result = test_instance.get_benefits([], non33_eligibilities, latest_ch33_eligibility)

        ch33_benefit = result.last
        expect(ch33_benefit[:benefit_type]).to eq('CH33')
        # 200 + 50 = 250 days = 8 months, 10 days
        expect(ch33_benefit[:amount_used]).to eq({ months: 8, days: 10 })
      end
    end
  end
end
