# frozen_string_literal: true

require 'rails_helper'
require 'survivors_benefits/structured_data/V2025/section_10'

RSpec.describe SurvivorsBenefits::StructuredData::V2025::Section10 do
  describe '#build_section10' do
    it 'merges has_reimbursement boolean fields' do
      form = { 'careExpenses' => [{}], 'medicalExpenses' => [{}] }
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new(form)
      service.build_section10
      expect(service.fields).to include(
        'UNREIMBURSED_MED_EXPENSES_Y' => true,
        'UNREIMBURSED_MED_EXPENSES_N' => false
      )
    end
  end

  describe '#any_reimbursement?' do
    it 'returns true if there are care expenses' do
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new({ 'careExpenses' => [{}] })
      expect(service.any_reimbursement?).to be true
    end

    it 'returns true if there are medical expenses' do
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new({ 'medicalExpenses' => [{}] })
      expect(service.any_reimbursement?).to be true
    end

    it 'returns false if there are no expenses' do
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new({})
      expect(service.any_reimbursement?).to be false
    end
  end

  describe '#merge_care_expense_fields' do
    it 'merges care expense fields including THSNDS/HNDRDS/CENTS breakdown' do
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
      expect(service.fields).to include(
        'CB_PROVIDER_TYPE_INHOMECARE1' => true,
        'CB_PROVIDER_TYPE_CAREFACILITY1' => false,
        'CB_EXPENSES_PAID_SP1' => true,
        'AMNT_YOU_PAY_1' => '200.45',
        'AMNT_YOU_PAY_1_THSNDS' => 0,
        'AMNT_YOU_PAY_1_HNDRDS' => 200,
        'AMNT_YOU_PAY_1_CENTS' => 45,
        'PROVIDER_START_DATE1' => '01/01/2020',
        'PROVIDER_END_DATE1' => nil,
        'CB_NO_END_DATE1' => true,
        'CB_PAYMENT_MONTHLY1' => true,
        'CB_PAYMENT_ANNUALLY1' => false
      )
    end
  end

  describe '#care_expense_currency_keys' do
    it 'returns full/thousands/hundreds/cents keys for expense_num' do
      service = SurvivorsBenefits::StructuredData::V2025::StructuredDataService.new({})
      expect(service.care_expense_currency_keys(1)).to eq(
        full: 'AMNT_YOU_PAY_1',
        thousands: 'AMNT_YOU_PAY_1_THSNDS',
        hundreds: 'AMNT_YOU_PAY_1_HNDRDS',
        cents: 'AMNT_YOU_PAY_1_CENTS'
      )
    end
  end

  describe '#merge_medical_expense_fields' do
    it 'merges medical expense fields including THSNDS/HNDRDS/CENTS breakdown' do
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
      expect(service.fields).to include(
        'MEDAMNT_YOU_PAY1' => '15,000.00',
        'MEDAMNT_YOU_PAY1_THSNDS' => 15,
        'MEDAMNT_YOU_PAY1_HNDRDS' => 0,
        'MEDAMNT_YOU_PAY1_CENTS' => 0,
        'MED_EXPENSES_SP1' => true,
        'MED_EXPENSES_VET1' => false,
        'MED_EXPENSES_CHILD1' => false,
        'PAID_TO_PROVIDER1' => 'Some provider',
        'DATE_COSTS_INCURRED_START1' => '05/05/2022',
        'CB_PMNT_FREQUENCY_MONTHLY1' => true,
        'CB_PMNT_FREQUENCY_ANNUALLY1' => false,
        'CB_PMNT_FREQUENCY_ONETIME1' => false
      )
    end
  end
end
