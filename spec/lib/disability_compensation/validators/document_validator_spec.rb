# frozen_string_literal: true

require 'rails_helper'
require 'disability_compensation/validators/document_validator'

RSpec.describe DisabilityCompensation::Validators::DocumentValidator do
  subject { described_class.new(file_path, attachment_id:) }

  let(:file_path) { Rails.root.join('spec', 'fixtures', 'files', 'doctors-note.pdf').to_s }
  let(:attachment_id) { 'L1839' }

  before do
    allow(StatsD).to receive(:increment)
  end

  describe '#validate' do
    context 'when OCR text contains both expected phrases' do
      before do
        allow_any_instance_of(RTesseract).to receive(:to_s)
          .and_return('Separation Health Assessment - Part A: Veteran Information')
      end

      it 'returns empty warnings array' do
        expect(subject.validate).to eq([])
      end

      it 'tracks match outcome metric' do
        subject.validate
        expect(StatsD).to have_received(:increment).with(
          'api.form526.document_validation.run',
          tags: ['outcome:match', 'attachment_id:L1839']
        )
      end
    end

    context 'when OCR text is missing expected phrases' do
      before do
        allow_any_instance_of(RTesseract).to receive(:to_s)
          .and_return('Some random document text without expected content')
      end

      it 'returns wrong_form warning' do
        expect(subject.validate).to eq(['wrong_form'])
      end

      it 'tracks mismatch outcome metric' do
        subject.validate
        expect(StatsD).to have_received(:increment).with(
          'api.form526.document_validation.run',
          tags: ['outcome:mismatch', 'attachment_id:L1839']
        )
      end
    end

    context 'when OCR text contains only one expected phrase' do
      before do
        allow_any_instance_of(RTesseract).to receive(:to_s)
          .and_return('Separation Health Assessment without the other phrase')
      end

      it 'returns wrong_form warning' do
        expect(subject.validate).to eq(['wrong_form'])
      end
    end

    context 'when OCR extraction fails' do
      before do
        allow_any_instance_of(RTesseract).to receive(:to_s).and_raise(RuntimeError, 'tesseract not found')
      end

      it 'returns unable_to_validate warning' do
        expect(subject.validate).to eq(['unable_to_validate'])
      end

      it 'logs the error with truncated message' do
        expect(Rails.logger).to receive(:error).with(
          'DocumentValidator OCR validation failed',
          hash_including(attachment_id: 'L1839', error_class: 'RuntimeError', error_message: 'tesseract not found')
        )
        subject.validate
      end

      it 'tracks error outcome metric' do
        subject.validate
        expect(StatsD).to have_received(:increment).with(
          'api.form526.document_validation.run',
          tags: ['outcome:error', 'attachment_id:L1839']
        )
      end
    end

    context 'when OCR extraction times out' do
      before do
        allow_any_instance_of(RTesseract).to receive(:to_s) { sleep(described_class::OCR_TIMEOUT + 1) }
        stub_const("#{described_class}::OCR_TIMEOUT", 0.01)
      end

      it 'returns unable_to_validate warning' do
        expect(subject.validate).to eq(['unable_to_validate'])
      end

      it 'logs the timeout with duration' do
        expect(Rails.logger).to receive(:error).with(
          'DocumentValidator OCR validation timed out',
          hash_including(attachment_id: 'L1839', timeout_seconds: 0.01)
        )
        subject.validate
      end

      it 'tracks timeout outcome metric' do
        subject.validate
        expect(StatsD).to have_received(:increment).with(
          'api.form526.document_validation.run',
          tags: ['outcome:timeout', 'attachment_id:L1839']
        )
      end
    end

    context 'when error message is excessively long' do
      let(:long_pii_message) { "Error processing document #{'x' * 300}" }

      before do
        allow_any_instance_of(RTesseract).to receive(:to_s).and_raise(RuntimeError, long_pii_message)
      end

      it 'truncates the error message to 200 characters' do
        expect(Rails.logger).to receive(:error).with(
          'DocumentValidator OCR validation failed',
          hash_including(error_message: a_string_matching(/\A.{200}\z/))
        )
        subject.validate
      end
    end

    context 'when file is an image' do
      let(:file_path) { Rails.root.join('spec', 'fixtures', 'files', 'doctors-note.jpg').to_s }

      before do
        allow(FileUtils).to receive(:cp)
        allow_any_instance_of(RTesseract).to receive(:to_s)
          .and_return('Separation Health Assessment Part A')
      end

      it 'processes image files without PDF conversion' do
        expect(MiniMagick::Image).not_to receive(:open)
        subject.validate
      end
    end

    context 'when attachment_id is not supported' do
      let(:attachment_id) { 'L029' }

      it 'returns empty warnings array without performing OCR' do
        expect_any_instance_of(described_class).not_to receive(:perform_ocr)
        expect(subject.validate).to eq([])
      end

      it 'tracks unsupported_attachment_id outcome with normalized attachment_id tag' do
        subject.validate
        expect(StatsD).to have_received(:increment).with(
          'api.form526.document_validation.run',
          tags: ['outcome:unsupported_attachment_id', 'attachment_id:unsupported']
        )
      end
    end

    context 'when attachment_id maps to a custom validator class' do
      let(:attachment_id) { 'L999' }
      let(:custom_validator_class) do
        Class.new do
          def validate(extracted_text)
            extracted_text.include?('Custom Keyword')
          end
        end
      end

      before do
        stub_const("#{described_class}::SUPPORTED_ATTACHMENT_IDS",
                   described_class::SUPPORTED_ATTACHMENT_IDS.merge('L999' => custom_validator_class))
      end

      it 'returns empty warnings when custom validator returns true' do
        allow_any_instance_of(RTesseract).to receive(:to_s).and_return('Contains Custom Keyword here')
        expect(subject.validate).to eq([])
      end

      it 'returns wrong_form warning when custom validator returns false' do
        allow_any_instance_of(RTesseract).to receive(:to_s).and_return('No relevant content')
        expect(subject.validate).to eq(['wrong_form'])
      end
    end
  end
end
