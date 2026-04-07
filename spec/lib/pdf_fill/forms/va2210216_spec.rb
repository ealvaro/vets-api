# frozen_string_literal: true

require 'rails_helper'
require 'pdf_fill/forms/va2210216'

describe PdfFill::Forms::Va2210216 do
  let(:form_data) { get_fixture('pdf_fill/22-10216/kitchen_sink') }
  let(:form) { described_class.new(form_data) }

  describe '#merge_fields' do
    subject(:merged_fields) { form.merge_fields }

    it 'formats full name of SCO' do
      official = form_data['certifyingOfficial']
      expect(merged_fields['certifyingOfficial']['fullName'])
        .to eq("#{official['first']} #{official['last']}")
    end

    it 'formats dates to MM/DD/YYYY' do
      [
        %w[institutionDetails termStartDate],
        %w[studentRatioCalcChapter dateOfCalculation],
        'dateSigned'

      ].each do |fields|
        expect(merged_fields.dig(*fields)).to match(%r{^(0[1-9]|1[0-2])/(0[1-9]|[12][0-9]|3[01])/\d{4}$})
      end
    end
  end
end
