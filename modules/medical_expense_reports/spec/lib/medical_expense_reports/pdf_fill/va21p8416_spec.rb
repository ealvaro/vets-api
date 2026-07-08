# frozen_string_literal: true

require 'rails_helper'
require 'lib/pdf_fill/fill_form_examples'
require 'medical_expense_reports/pdf_fill/va21p8416'
require 'pdf_utilities/datestamp_pdf'
require 'pdf/reader'
require 'fileutils'
require 'tmpdir'
require 'timecop'

describe MedicalExpenseReports::PdfFill::Va21p8416 do
  include SchemaMatchers

  describe '#to_pdf' do
    it 'merges the right keys' do
      Timecop.freeze(Time.zone.parse('2025-10-21')) do
        files = %w[diffs kitchen-sink_us-number]
        files.map do |file|
          f1 = File.read File.join(__dir__, 'input', "21p-8416_#{file}.json")

          claim = MedicalExpenseReports::SavedClaim.new(form: f1)

          form_id = MedicalExpenseReports::FORM_ID
          form_class = MedicalExpenseReports::PdfFill::Va21p8416
          fill_options = {
            created_at: '2025-10-08'
          }
          merged_form_data = form_class.new(claim.parsed_form).merge_fields(fill_options)
          submit_date = Utilities::DateParser.parse(
            fill_options[:created_at]
          )

          hash_converter = PdfFill::Filler.make_hash_converter(form_id, form_class, submit_date, fill_options)
          new_hash = hash_converter.transform_data(form_data: merged_form_data, pdftk_keys: form_class::KEY)

          f2 = File.read File.join(__dir__, 'output', "21p-8416_#{file}.json")
          data = JSON.parse(f2)

          expect(new_hash).to eq(data)
        end
      end
    end
  end

  describe '.stamp_signature' do
    let(:pdf_path) { '/tmp/test_form.pdf' }
    let(:stamped_path) { '/tmp/test_form_stamped.pdf' }
    let(:datestamp_instance) { instance_double(PDFUtilities::DatestampPdf) }
    let(:coordinates) { { x: 123, y: 456, page_number: 7 } }

    before do
      allow(PDFUtilities::DatestampPdf).to receive(:new).with(pdf_path).and_return(datestamp_instance)
      allow(described_class).to receive(:signature_overlay_coordinates).and_return(coordinates)
    end

    it 'stamps the signature when present' do
      expect(datestamp_instance).to receive(:run).with(
        text: 'Jane Doe',
        x: coordinates[:x],
        y: coordinates[:y],
        page_number: coordinates[:page_number],
        size: described_class::SIGNATURE_FONT_SIZE,
        text_only: true,
        timestamp: '',
        template: pdf_path,
        multistamp: true
      ).and_return(stamped_path)

      result = described_class.stamp_signature(pdf_path, { 'statementOfTruthSignature' => 'Jane Doe' })
      expect(result).to eq(stamped_path)
    end

    it 'returns the original PDF when signature is blank' do
      result = described_class.stamp_signature(pdf_path, { 'statementOfTruthSignature' => '' })
      expect(result).to eq(pdf_path)
      expect(PDFUtilities::DatestampPdf).not_to have_received(:new)
    end

    it 'rescues errors and returns the original PDF path' do
      allow(datestamp_instance).to receive(:run).and_raise(StandardError, 'boom')

      result = described_class.stamp_signature(pdf_path, { 'statementOfTruthSignature' => 'Jane Doe' })
      expect(result).to eq(pdf_path)
    end
  end

  describe '.authentication_stamp_text' do
    it 'returns the identity-verified sentence for LOA 3 (IAL2)' do
      expect(described_class.authentication_stamp_text(3))
        .to eq('Signee signed with an identity-verified account.')
    end

    it 'returns the signed-in-but-unverified sentence for LOA 1 (IAL1)' do
      expect(described_class.authentication_stamp_text(1))
        .to eq('Signee signed in but hasn’t verified their identity.')
    end

    it 'returns the not-signed-in sentence when unauthenticated (nil LOA)' do
      expect(described_class.authentication_stamp_text(nil)).to eq('Signee not signed in.')
    end
  end

  describe '.stamp_submission_footer' do
    let(:timestamp) { Time.utc(2023, 12, 13, 11, 30) }

    it 'returns the original PDF (untouched) when the timestamp is blank' do
      expect(HexaPDF::Document).not_to receive(:open)

      expect(described_class.stamp_submission_footer('/tmp/does_not_matter.pdf', nil, 3))
        .to eq('/tmp/does_not_matter.pdf')
    end

    it 'fails open on stamping errors: logs, emits a metric, and returns the original PDF' do
      allow(HexaPDF::Document).to receive(:open).and_raise(StandardError, 'boom')
      allow(Rails.logger).to receive(:error)
      allow(StatsD).to receive(:increment)

      result = described_class.stamp_submission_footer('/tmp/x.pdf', timestamp, 3)

      expect(result).to eq('/tmp/x.pdf')
      expect(StatsD).to have_received(:increment).with(described_class::SUBMISSION_STAMP_ERROR_METRIC)
    end

    context 'with a real multi-page PDF' do
      let(:source) { "#{Common::FileHelpers.random_file_path}.pdf" }
      let(:outputs) { [] }

      before do
        doc = HexaPDF::Document.new
        2.times { doc.pages.add }
        doc.write(source)
      end

      after do
        Common::FileHelpers.delete_file_if_exists(source)
        outputs.each { |p| Common::FileHelpers.delete_file_if_exists(p) }
      end

      it 'renders the two-line watermark (timestamp + IAL2 auth) on every page' do
        out = described_class.stamp_submission_footer(source, timestamp, 3)
        outputs << out

        reader = PDF::Reader.new(out)
        expect(reader.pages.size).to eq(2)
        reader.pages.each do |page|
          expect(page.text).to include('Signed electronically and submitted via VA.gov at 11:30 UTC 2023-12-13.')
          expect(page.text).to include('Signee signed with an identity-verified account.')
        end
      end

      it 'renders the unauthenticated auth line when LOA is nil' do
        out = described_class.stamp_submission_footer(source, timestamp, nil)
        outputs << out

        expect(PDF::Reader.new(out).pages.first.text).to include('Signee not signed in.')
      end
    end
  end
end
