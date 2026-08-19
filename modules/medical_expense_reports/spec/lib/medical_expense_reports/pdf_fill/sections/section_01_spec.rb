# frozen_string_literal: true

require 'rails_helper'
require 'medical_expense_reports/pdf_fill/sections/section_01'

describe MedicalExpenseReports::PdfFill::Section1 do
  describe '#expand' do
    it 'titlecases all-caps veteran names without splitting on inflection acronyms' do
      form_data = { 'veteranFullName' => { 'first' => 'VANESSA', 'middle' => 'Quinn', 'last' => 'SMITH-JONES' } }

      described_class.new.expand(form_data)

      expect(form_data['veteranFullName']).to eq({ 'first' => 'Vanessa', 'middle' => 'Q', 'last' => 'Smith-Jones' })
    end

    it 'handles missing names' do
      form_data = {}

      described_class.new.expand(form_data)

      expect(form_data['veteranFullName']).to eq({ 'first' => nil, 'middle' => nil, 'last' => nil })
    end
  end
end
