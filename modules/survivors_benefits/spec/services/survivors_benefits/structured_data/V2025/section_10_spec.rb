# frozen_string_literal: true

require 'rails_helper'
require 'survivors_benefits/structured_data/V2025/section_10'

RSpec.describe SurvivorsBenefits::StructuredData::V2025::Section10 do
  describe '#merge_care_expense_fields' do
    it 'emits a single AMNT_YOU_PAY field with no THSNDS/HNDRDS/CENTS breakdown' do
      care_expenses = [
        {
          'careType' => 'IN_HOME_CARE_ATTENDANT',
          'recipient' => 'SURVIVING_SPOUSE',
          'provider' => 'Some provider',
          'careDateRange' => { 'from' => '2020-01-01' },
          'paymentAmount' => 200.45,
          'noCareEndDate' => true,
          'paymentFrequency' => 'MONTHLY',
          'hoursPerWeek' => 20,
          'ratePerHour' => 15
        }
      ]
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new({})
      service.merge_care_expense_fields(care_expenses)
      expect(service.fields['AMNT_YOU_PAY1']).to eq('200.45')
      expect(service.fields.keys).not_to include('AMNT_YOU_PAY1_THSNDS', 'AMNT_YOU_PAY1_HNDRDS', 'AMNT_YOU_PAY1_CENTS')
    end
  end

  describe '#merge_care_type_fields' do
    it 'supports NURSING_HOME and RESIDENTIAL_CARE in addition to existing care types' do
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new({})
      service.merge_care_type_fields(1, 'NURSING_HOME')
      expect(service.fields).to include(
        'CB_PROVIDER_TYPE_NURSINGHOME1' => true,
        'CB_PROVIDER_TYPE_DAYCARE1' => false,
        'CB_PROVIDER_TYPE_CAREFACILITY1' => false,
        'CB_PROVIDER_TYPE_INHOMECARE1' => false
      )
    end

    it 'sets RESIDENTIAL_CARE correctly' do
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new({})
      service.merge_care_type_fields(2, 'RESIDENTIAL_CARE')
      expect(service.fields).to include(
        'CB_PROVIDER_TYPE_NURSINGHOME2' => false,
        'CB_PROVIDER_TYPE_DAYCARE2' => true
      )
    end
  end

  describe '#merge_medical_expense_fields' do
    it 'emits a single MEDAMNT_YOU_PAY field with no THSNDS/HNDRDS/CENTS breakdown' do
      medical_expenses = [
        {
          'recipient' => 'SURVIVING_SPOUSE',
          'provider' => 'Some provider',
          'purpose' => 'Some purpose',
          'paymentDate' => '2022-05-05',
          'paymentAmount' => 15_000,
          'paymentFrequency' => 'MONTHLY'
        }
      ]
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new({})
      service.merge_medical_expense_fields(medical_expenses)
      expect(service.fields['MEDAMNT_YOU_PAY1']).to eq('15,000.00')
      expect(service.fields.keys).not_to include('MEDAMNT_YOU_PAY1_THSNDS')
    end

    it 'accepts recipients key as fallback for recipient' do
      medical_expenses = [
        {
          'recipients' => 'VETERAN',
          'paymentAmount' => 100,
          'paymentFrequency' => 'ONE_TIME'
        }
      ]
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new({})
      service.merge_medical_expense_fields(medical_expenses)
      expect(service.fields).to include(
        'MED_EXPENSES_VET1' => true,
        'MED_EXPENSES_SP1' => false
      )
    end
  end
end
