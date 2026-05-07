# frozen_string_literal: true

require 'rails_helper'
require 'action_dispatch/http/mime_type'
require 'shrine'
require 'shrine/plugins/validate_pdf_integrity'

describe Shrine::Plugins::ValidatePdfIntegrity do
  let(:klass) do
    Class.new do
      include Shrine::Plugins::ValidatePdfIntegrity::AttacherMethods

      def get
        raise "shouldn't be called"
      end

      def errors
        @errors ||= []
      end
    end
  end

  let(:instance) { klass.new }

  def stub_attachment(file, mime_type: 'application/pdf', size: nil)
    file_size = size || (file.respond_to?(:size) ? file.size : File.size(file))
    attachment = instance_double(Shrine::UploadedFile, mime_type:, size: file_size)

    allow(attachment).to receive(:download) do |&block|
      file.rewind if file.respond_to?(:rewind)
      block ? block.call(file) : file
    end

    allow(instance).to receive(:get).and_return(attachment)
    attachment
  end

  def write_tempfile(name, content)
    file = Tempfile.new([name, '.pdf'], binmode: true)
    file.write(content)
    file.rewind
    file
  end

  describe '#validate_pdf_integrity' do
    context 'when file is not a PDF' do
      before { stub_attachment(nil, mime_type: 'image/jpeg', size: 0) }

      it 'skips validation entirely' do
        expect { instance.validate_pdf_integrity }
          .not_to(change { instance.errors.count })
      end

      it 'does not call download' do
        expect(instance.get).not_to receive(:download)
        instance.validate_pdf_integrity
      end
    end

    context 'when PDF is valid with pages' do
      let(:fixture_path) { Rails.root.join('spec', 'fixtures', 'files', 'doctors-note.pdf') }
      let(:file) { File.open(fixture_path, 'rb') }

      before { stub_attachment(file) }
      after  { file.close }

      it 'does not add an error' do
        expect { instance.validate_pdf_integrity }
          .not_to(change { instance.errors.count })
      end

      it 'parses every page (forces deep parse, not just page_count)' do
        reader_spy = instance_double(PDF::Reader, page_count: 2, pages: [])
        allow(reader_spy).to receive(:pages).and_return(
          Array.new(2) { instance_double(PDF::Reader::Page, raw_content: 'stream') }
        )
        allow(PDF::Reader).to receive(:new).and_return(reader_spy)

        instance.validate_pdf_integrity

        expect(reader_spy.pages).to all(have_received(:raw_content))
      end
    end

    context 'when PDF has zero pages' do
      let(:zero_page_pdf) do
        write_tempfile('zero_pages', <<~PDF)
          %PDF-1.4
          1 0 obj
          << /Type /Catalog /Pages 2 0 R >>
          endobj
          2 0 obj
          << /Type /Pages /Kids [] /Count 0 >>
          endobj
          xref
          0 3
          0000000000 65535 f#{' '}
          0000000009 00000 n#{' '}
          0000000058 00000 n#{' '}
          trailer
          << /Size 3 /Root 1 0 R >>
          startxref
          109
          %%EOF
        PDF
      end

      before { stub_attachment(zero_page_pdf) }

      after do
        zero_page_pdf.close
        zero_page_pdf.unlink
      end

      it 'adds the invalid-pdf error' do
        instance.validate_pdf_integrity
        expect(instance.errors).to contain_exactly(
          I18n.t('errors.messages.uploads.pdf.invalid')
        )
      end

      it 'logs the rejection with reason: empty_pdf' do
        expect(Rails.logger).to receive(:warn).with(
          'validate_pdf_integrity rejected file',
          hash_including(reason: 'empty_pdf')
        )
        instance.validate_pdf_integrity
      end
    end

    context 'when PDF construction raises MalformedPDFError' do
      let(:file) { write_tempfile('malformed', '%PDF-1.4 this is not valid pdf content') }

      before { stub_attachment(file) }

      after do
        file.close
        file.unlink
      end

      it 'adds the malformed-pdf error' do
        instance.validate_pdf_integrity
        expect(instance.errors).to contain_exactly(
          I18n.t('errors.messages.uploads.malformed_pdf')
        )
      end

      it 'logs the rejection with the error class name' do
        expect(Rails.logger).to receive(:warn).with(
          'validate_pdf_integrity rejected file',
          hash_including(reason: a_string_matching(/malformed/i))
        )
        instance.validate_pdf_integrity
      end
    end

    context 'when a page raises Zlib::DataError during deep parse' do
      let(:file) { write_tempfile('zlib_data', '%PDF-1.4') }

      before do
        stub_attachment(file)
        page = instance_double(PDF::Reader::Page)
        allow(page).to receive(:raw_content).and_raise(Zlib::DataError, 'invalid block type')
        reader = instance_double(PDF::Reader, page_count: 1, pages: [page])
        allow(PDF::Reader).to receive(:new).and_return(reader)
      end

      after do
        file.close
        file.unlink
      end

      it 'adds the malformed-pdf error instead of crashing' do
        instance.validate_pdf_integrity
        expect(instance.errors).to contain_exactly(
          I18n.t('errors.messages.uploads.malformed_pdf')
        )
      end

      it 'logs the rejection with reason: data_error' do
        expect(Rails.logger).to receive(:warn).with(
          'validate_pdf_integrity rejected file',
          hash_including(reason: 'data_error')
        )
        instance.validate_pdf_integrity
      end
    end

    context 'when a page raises Zlib::BufError during deep parse' do
      let(:file) { write_tempfile('zlib_buf', '%PDF-1.4') }

      before do
        stub_attachment(file)
        page = instance_double(PDF::Reader::Page)
        allow(page).to receive(:raw_content).and_raise(Zlib::BufError)
        reader = instance_double(PDF::Reader, page_count: 1, pages: [page])
        allow(PDF::Reader).to receive(:new).and_return(reader)
      end

      after do
        file.close
        file.unlink
      end

      it 'adds the malformed-pdf error instead of crashing' do
        instance.validate_pdf_integrity
        expect(instance.errors).to contain_exactly(
          I18n.t('errors.messages.uploads.malformed_pdf')
        )
      end
    end

    context 'when PDF::Reader raises EncryptedPDFError' do
      let(:file) { write_tempfile('encrypted', '%PDF-1.4') }

      before do
        stub_attachment(file)
        allow(PDF::Reader).to receive(:new).and_raise(PDF::Reader::EncryptedPDFError)
      end

      after do
        file.close
        file.unlink
      end

      it 'adds the malformed-pdf error (validate_unlocked_pdf handles encryption separately)' do
        instance.validate_pdf_integrity
        expect(instance.errors).to contain_exactly(
          I18n.t('errors.messages.uploads.malformed_pdf')
        )
      end
    end

    context 'when PDF::Reader raises UnsupportedFeatureError' do
      let(:file) { write_tempfile('unsupported', '%PDF-1.4') }

      before do
        stub_attachment(file)
        allow(PDF::Reader).to receive(:new).and_raise(PDF::Reader::UnsupportedFeatureError)
      end

      after do
        file.close
        file.unlink
      end

      it 'adds the malformed-pdf error' do
        instance.validate_pdf_integrity
        expect(instance.errors).to contain_exactly(
          I18n.t('errors.messages.uploads.malformed_pdf')
        )
      end
    end

    context 'when an unexpected StandardError leaks from the parser' do
      let(:file) { write_tempfile('weird', '%PDF-1.4') }

      before do
        stub_attachment(file)
        allow(PDF::Reader).to receive(:new).and_raise(IOError, 'stream closed prematurely')
      end

      after do
        file.close
        file.unlink
      end

      it 'is caught and surfaced as a validation error rather than a 500' do
        expect { instance.validate_pdf_integrity }.not_to raise_error
        expect(instance.errors).to contain_exactly(
          I18n.t('errors.messages.uploads.malformed_pdf')
        )
      end

      it 'logs with reason: unexpected_error and includes the original class' do
        expect(Rails.logger).to receive(:warn).with(
          'validate_pdf_integrity rejected file',
          hash_including(reason: 'unexpected_error', detail: a_string_matching(/IOError/))
        )
        instance.validate_pdf_integrity
      end
    end

    context 'tempfile cleanup' do
      let(:file) { write_tempfile('cleanup', '%PDF-1.4') }

      after do
        file.close unless file.closed?
        file.unlink if File.exist?(file.path)
      end

      it 'uses the block form of download so Shrine cleans up the tempfile' do
        attachment = stub_attachment(file)

        expect(attachment).to receive(:download).with(no_args) do |&block|
          expect(block).not_to be_nil
          file.rewind
          block.call(file)
        end

        instance.validate_pdf_integrity
      end
    end
  end
end
