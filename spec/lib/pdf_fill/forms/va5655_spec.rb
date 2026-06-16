# frozen_string_literal: true

require 'rails_helper'
require 'pdf_fill/forms/va5655'
require 'pdf_fill/filler'
require 'pdf_fill/hash_converter'
require 'lib/pdf_fill/fill_form_examples'

describe PdfFill::Forms::Va5655 do
  describe '#merge_fields' do
    it 'merges the right fields', run_at: '2016-12-31 00:00:00 EDT' do
      expect(described_class.new(get_fixture('pdf_fill/5655/simple')).merge_fields).to eq(
        get_fixture('pdf_fill/5655/merge_fields')
      )
    end
  end

  describe 'additionalComments overflow' do
    subject(:overflows?) { converter.overflow?(key_data, value) }

    let(:key_data) { described_class::KEY.dig('additionalData', 'additionalComments') }
    let(:converter) do
      PdfFill::HashConverter.new(
        '%m/%d/%Y',
        instance_double(PdfFill::ExtrasGenerator, placeholder_text: 'See add\'l info', use_hexapdf: false)
      )
    end

    context 'when the comment spans 3 lines or fewer' do
      let(:value) { "line one\nline two\nline three" }

      it { is_expected.to be false }
    end

    context 'when the comment spans more than 3 lines' do
      let(:value) { "line one\nline two\nline three\nline four" }

      it { is_expected.to be true }
    end

    context 'when the comment is within the 450 character limit' do
      let(:value) { 'a' * 450 }

      it { is_expected.to be false }
    end

    context 'when the comment exceeds the 450 character limit' do
      let(:value) { 'a' * 451 }

      it { is_expected.to be true }
    end
  end
end
