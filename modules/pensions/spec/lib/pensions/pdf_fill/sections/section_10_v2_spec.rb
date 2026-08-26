# frozen_string_literal: true

require 'rails_helper'
require 'pensions/pdf_fill/sections/section_08_v2'

describe Pensions::PdfFill::Section10V2 do
  describe '#expand' do
    subject(:expand) { described_class.new.expand(form_data) }

    let(:form_data) do
      {
        'careExpenses' => care_expenses,
        'medicalExpenses' => medical_expenses
      }
    end
    let(:care_expenses) { [care_expense] }
    let(:care_expense) do
      {
        'recipients' => 'VETERAN',
        'provider' => 'Family Medical Facility',
        'careType' => 'CARE_FACILITY',
        'ratePerHour' => 100.75,
        'hoursPerMonth' => '20',
        'careDateRange' => {
          'from' => '2020-01-31',
          'to' => '2026-01-31'
        },
        'paymentFrequency' => 'ONCE_MONTH',
        'paymentAmount' => 2500
      }
    end
    let(:medical_expenses) do
      [
        {
          'receipients' => 'SPOUSE',
          'provider' => 'Care Assocites',
          'purpose' => 'Funeral expenses',
          'paymentFrequency' => 'ONE_TIME',
          'paymentDate' => '2026-08-24',
          'paymentAmount' => 1_000
        }
      ]
    end

    before { allow(Pensions).to receive(:use_v2?).and_return(true) }

    it 'sets hasAnyExpenses to radio no if neither care nor medical expenses and returns early' do
      form_data.delete('careExpenses')
      form_data.delete('medicalExpenses')
      expect(expand).to be_nil
      expect(form_data['hasAnyExpenses']).to eq(1)
    end

    it 'sets hasAnyExpenses to radio yes if care expenses present but not medical expenses' do
      form_data.delete('medicalExpenses')
      expand
      expect(form_data['hasAnyExpenses']).to eq(0)
    end

    it 'sets hasAnyExpenses to radio yes if medical expenses present but not care expenses' do
      form_data.delete('careExpenses')
      expand
      expect(form_data['hasAnyExpenses']).to eq(0)
    end

    it 'formats recipient for overflow' do
      recipient = care_expense['recipients']
      expand
      expect(care_expense['recipientsOverflow']).to eq(recipient.humanize)
    end

    it 'formats payment frequency for overflow' do
      frequency = care_expense['paymentFrequency']
      expand
      expect(care_expense['paymentFrequencyOverflow']).to eq(frequency)
    end

    context 'when care expense' do
      it 'formats care type overflow' do
        care_type = care_expense['careType']
        expand
        expect(care_expense['careTypeOverflow']).to eq(care_type.humanize)
      end

      # TODO: Remove when backward compatibility no longer necessary
      it 'handles legacy hoursPerWeek field as hoursPerMonth' do
        hours = care_expense.delete('hoursPerMonth')
        care_expense['hoursPerWeek'] = hours
        expand
        expect(care_expense['hoursPerMonth']).to eq(hours)
      end

      it 'formats care date range overflow' do
        date_range = described_class.new.build_date_range_string(care_expense['careDateRange'])
        expand
        expect(care_expense['careDateRangeOverflow']).to eq(date_range)
      end

      it 'sets noCareEndDate to checkbox on if boolean field nil and date range missing to field' do
        care_expense['careDateRange'].delete('to')
        expand
        expect(care_expense['noCareEndDate']).to eq('Yes')
      end

      it 'sets noCareEndDate to checkbox on if boolean field nil and date range to field is blank' do
        care_expense['careDateRange']['to'] = ''
        expand
        expect(care_expense['noCareEndDate']).to eq('Yes')
      end

      it 'sets noCareEndDate to checkbox off if boolean field nil and date range has to field' do
        expand
        expect(care_expense['noCareEndDate']).to eq('Off')
      end

      it 'sets noCareEndDate to checkbox on if no care date range' do
        care_expense.delete('careDateRange')
        expand
        expect(care_expense['noCareEndDate']).to eq('Yes')
      end

      it 'sets noCareEndDate to checkbox off if boolean field false' do
        care_expense['noCareEndDate'] = false
        expand
        expect(care_expense['noCareEndDate']).to eq('Off')
      end

      it 'sets noCareEndDate to checkbox on if boolean field true' do
        care_expense['noCareEndDate'] = true
        expand
        expect(care_expense['noCareEndDate']).to eq('Yes')
      end
    end
  end
end
