# frozen_string_literal: true

require 'rails_helper'
require 'mini_magick'
require 'common/convert_to_pdf'

RSpec.describe IvcChampva::PdfConverter do
  subject(:converter) { described_class.new(uploaded_file) }

  let(:uploaded_file) do
    ActionDispatch::Http::UploadedFile.new(
      tempfile: Tempfile.new(['test', '.heic']),
      filename: 'test.heic',
      type: 'image/heic'
    )
  end

  before do
    allow(Flipper).to receive(:enabled?).and_call_original
    allow(Flipper).to receive(:enabled?).with(:champva_auto_resize_on_upload).and_return(true)
  end

  describe '#convert_to_pdf' do
    context 'when the auto-resize flag is disabled' do
      let(:pdf_double) { instance_double(Common::ConvertToPdf, run: 'tmp/delegated.pdf') }

      before do
        allow(Flipper).to receive(:enabled?).with(:champva_auto_resize_on_upload).and_return(false)
        allow(Common::ConvertToPdf).to receive(:new).with(uploaded_file).and_return(pdf_double)
      end

      it 'delegates to Common::ConvertToPdf and skips JPEG compression' do
        expect(MiniMagick).not_to receive(:convert)

        expect(converter.convert_to_pdf).to eq('tmp/delegated.pdf')
        expect(Common::ConvertToPdf).to have_received(:new).with(uploaded_file)
      end
    end

    context 'when the upload is already a PDF (flag enabled)' do
      let(:uploaded_file) do
        ActionDispatch::Http::UploadedFile.new(
          tempfile: Tempfile.new(['test', '.pdf']),
          filename: 'test.pdf',
          type: 'application/pdf'
        )
      end
      let(:pdf_double) { instance_double(Common::ConvertToPdf, run: 'tmp/delegated.pdf') }

      before do
        allow(Common::ConvertToPdf).to receive(:new).with(uploaded_file).and_return(pdf_double)
      end

      it 'short-circuits to Common::ConvertToPdf and skips JPEG compression' do
        expect(MiniMagick).not_to receive(:convert)

        expect(converter.convert_to_pdf).to eq('tmp/delegated.pdf')
        expect(Common::ConvertToPdf).to have_received(:new).with(uploaded_file)
      end
    end

    context 'when conversion succeeds' do
      before do
        allow(Common::FileHelpers).to receive(:random_file_path).and_return('tmp/result')
        allow(MiniMagick).to receive(:convert)
      end

      it 'returns the PDF file path' do
        expect(converter.convert_to_pdf).to eq('tmp/result.pdf')
      end
    end

    context 'when ImageMagick raises an unsupported HEIC codec error' do
      before do
        allow(MiniMagick).to receive(:convert)
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
        allow(MiniMagick).to receive(:convert)
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
        allow(MiniMagick).to receive(:convert)
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
