# frozen_string_literal: true

require 'rails_helper'
require 'mini_magick'

RSpec.describe IvcChampva::PdfConverter do
  subject(:converter) { described_class.new(uploaded_file) }

  let(:uploaded_file) do
    ActionDispatch::Http::UploadedFile.new(
      tempfile: Tempfile.new(['test', '.heic']),
      filename: 'test.heic',
      type: 'image/heic'
    )
  end

  let(:pdf_double) { instance_double(Common::ConvertToPdf) }

  before do
    allow(Common::ConvertToPdf).to receive(:new).with(uploaded_file).and_return(pdf_double)
  end

  describe '#convert_to_pdf' do
    context 'when conversion succeeds' do
      before { allow(pdf_double).to receive(:run).and_return('/tmp/result.pdf') }

      it 'returns the PDF file path' do
        expect(converter.convert_to_pdf).to eq('/tmp/result.pdf')
      end
    end

    context 'when ImageMagick raises an unsupported HEIC codec error' do
      before do
        allow(pdf_double).to receive(:run)
          .and_raise(MiniMagick::Error.new('magick: Unsupported feature: Unspecified: Internal error (4.0)'))
      end

      it 'raises UnprocessableEntity with a user-friendly message' do
        expect { converter.convert_to_pdf }
          .to raise_error(Common::Exceptions::UnprocessableEntity) do |error|
            expect(error.errors.first.detail).to include('unsupported codec')
          end
      end

      it 'logs a warning with the codec error' do
        expect(Rails.logger).to receive(:warn)
          .with(/IVC ChampVA PDF conversion rejected unsupported HEIC codec/)

        expect { converter.convert_to_pdf }
          .to raise_error(Common::Exceptions::UnprocessableEntity)
      end
    end

    context 'when ImageMagick raises a non-codec MiniMagick error' do
      before do
        allow(pdf_double).to receive(:run)
          .and_raise(MiniMagick::Error.new('some other magick failure'))
      end

      it 're-raises the MiniMagick error' do
        expect { converter.convert_to_pdf }.to raise_error(MiniMagick::Error)
      end

      it 'logs the error' do
        expect(Rails.logger).to receive(:error)
          .with('IVC ChampVA Forms - Failed to convert file to PDF: some other magick failure')

        expect { converter.convert_to_pdf }.to raise_error(MiniMagick::Error)
      end
    end

    context 'when a non-MiniMagick error occurs' do
      before do
        allow(pdf_double).to receive(:run)
          .and_raise(StandardError.new('unexpected failure'))
      end

      it 're-raises the error' do
        expect { converter.convert_to_pdf }.to raise_error(StandardError)
      end

      it 'logs the error' do
        expect(Rails.logger).to receive(:error)
          .with('IVC ChampVA Forms - Failed to convert file to PDF: unexpected failure')

        expect { converter.convert_to_pdf }.to raise_error(StandardError)
      end
    end
  end
end
