# frozen_string_literal: true

require 'rails_helper'
require 'medical_expense_reports/pdf_fill/sections/section_02'

describe MedicalExpenseReports::PdfFill::Section2 do
  describe '#expand' do
    it 'titlecases all-caps claimant names without splitting on inflection acronyms' do
      form_data = { 'claimantFullName' => { 'first' => 'VANESSA', 'middle' => 'Quinn', 'last' => 'SMITH-JONES' } }

      described_class.new.expand(form_data)

      expect(form_data['claimantFullName']).to eq({ 'first' => 'Vanessa', 'middle' => 'Q', 'last' => 'Smith-Jones' })
    end
  end
end
