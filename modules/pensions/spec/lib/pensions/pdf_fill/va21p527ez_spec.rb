# frozen_string_literal: true

require 'rails_helper'
require 'pensions/pdf_fill/va21p527ez'
require 'lib/pdf_fill/fill_form_examples'

def basic_class
  Pensions::PdfFill::Va21p527ez.new({})
end

describe Pensions::PdfFill::Va21p527ez do
  include SchemaMatchers

  let(:form_data) do
    VetsJsonSchema::EXAMPLES.fetch('21P-527EZ-KITCHEN_SINK')
  end

  context 'when pension_pdf_form_alignment flipper is disabled' do
    it_behaves_like 'a form filler', {
      form_id: described_class::FORM_ID,
      factory: :pensions_saved_claim,
      use_vets_json_schema: true,
      input_data_fixture_dir: 'modules/pensions/spec/fixtures',
      output_pdf_fixture_dir: 'modules/pensions/spec/fixtures',
      use_ocr: true,
      ocr_end_page: 7,
      fill_options: { extras_redesign: true, omit_esign_stamp: true },
      flipper_states: { pension_pdf_form_alignment: false }
    }
  end

  context 'when pension_pdf_form_alignment flipper is enabled' do
    it_behaves_like 'a form filler', {
      form_id: described_class::FORM_ID,
      factory: :pensions_saved_claim,
      use_vets_json_schema: true,
      input_data_fixture_dir: 'modules/pensions/spec/fixtures/v2',
      output_pdf_fixture_dir: 'modules/pensions/spec/fixtures/v2',
      use_ocr: true,
      ocr_end_page: 7,
      fill_options: { extras_redesign: true, omit_esign_stamp: true },
      flipper_states: { pension_pdf_form_alignment: true }
    }
  end

  describe '#merge_fields' do
    let(:fixture_path) { "#{Pensions::MODULE_PATH}/spec/fixtures/#{file_path}" }

    shared_examples 'form data merger' do
      it 'merges the right fields' do
        Timecop.freeze(Time.zone.parse('2016-12-31 00:00:00 EDT')) do
          expected = get_fixture_absolute(fixture_path)
          actual = described_class.new(form_data).merge_fields

          # Create a diff that is easy to read when expected/actual differ
          diff = Hashdiff.diff(expected, actual)

          expect(diff).to eq([])
        end
      ensure
        Timecop.return
      end
    end

    context 'when pension_pdf_form_alignment flipper is disabled' do
      let(:file_path) { 'merge_fields' }

      before { allow(Flipper).to receive(:enabled?).with(:pension_pdf_form_alignment).and_return(false) }

      it_behaves_like 'form data merger'
    end

    context 'when pension_pdf_form_alignment flipper is enabled' do
      let(:file_path) { 'v2/merge_fields_v2' }

      before { allow(Flipper).to receive(:enabled?).with(:pension_pdf_form_alignment).and_return(true) }

      it_behaves_like 'form data merger'
    end
  end

  describe '#start_page' do
    context 'when pension_pdf_form_alignment flipper is disabled' do
      before { allow(Flipper).to receive(:enabled?).with(:pension_pdf_form_alignment).and_return(false) }

      it 'returns V1 overflow start page' do
        expect(described_class.new({}).start_page).to eq(described_class::START_PAGE_V1)
      end
    end

    context 'when pension_pdf_form_alignment flipper is enabled' do
      before { allow(Flipper).to receive(:enabled?).with(:pension_pdf_form_alignment).and_return(true) }

      it 'returns V2 overflow start page' do
        expect(described_class.new({}).start_page).to eq(described_class::START_PAGE_V2)
      end
    end
  end

  describe '#question_key' do
    context 'when pension_pdf_form_alignment flipper is disabled' do
      before { allow(Flipper).to receive(:enabled?).with(:pension_pdf_form_alignment).and_return(false) }

      it 'returns V1 question key' do
        expect(described_class.new({}).question_key).to eq(described_class::QUESTION_KEY_V1)
      end
    end

    context 'when pension_pdf_form_alignment flipper is enabled' do
      before { allow(Flipper).to receive(:enabled?).with(:pension_pdf_form_alignment).and_return(true) }

      it 'returns V2 overflow start page' do
        expect(described_class.new({}).question_key).to eq(described_class::QUESTION_KEY_V2)
      end
    end
  end

  describe '#section_classes' do
    context 'when pension_pdf_form_alignment flipper is disabled' do
      before { allow(Flipper).to receive(:enabled?).with(:pension_pdf_form_alignment).and_return(false) }

      it 'returns V1 section classes' do
        expect(described_class.new({}).section_classes).to eq(described_class::SECTION_CLASSES_V1)
      end
    end

    context 'when pension_pdf_form_alignment flipper is enabled' do
      before { allow(Flipper).to receive(:enabled?).with(:pension_pdf_form_alignment).and_return(true) }

      it 'returns V2 overflow start page' do
        expect(described_class.new({}).section_classes).to eq(described_class::SECTION_CLASSES_V2)
      end
    end
  end

  describe '#template' do
    before { allow(Pensions).to receive(:pdf_path).and_call_original }

    context 'when pension_pdf_form_alignment flipper is disabled' do
      before { allow(Flipper).to receive(:enabled?).with(:pension_pdf_form_alignment).and_return(false) }

      it 'delegates to Pensions.pdf_path' do
        described_class.new({}).template
        expect(Pensions).to have_received(:pdf_path).once
      end
    end

    context 'when pension_pdf_form_alignment flipper is enabled' do
      before { allow(Flipper).to receive(:enabled?).with(:pension_pdf_form_alignment).and_return(true) }

      it 'delegates to Pensions.pdf_path' do
        described_class.new({}).template
        expect(Pensions).to have_received(:pdf_path).once
      end
    end
  end
end
