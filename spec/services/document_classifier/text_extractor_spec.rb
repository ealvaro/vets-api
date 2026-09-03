# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DocumentClassifier::TextExtractor do
  describe '.call' do
    it 'returns UTF-8 text and extraction metadata for a plain-text document' do
      allow(Marcel::MimeType).to receive(:for).and_return('text/plain')

      result = described_class.call("example text\xFF".b, filename: 'example.txt')

      expect(result).to include(
        'text' => "example text\uFFFD",
        'method' => 'plain_text',
        'mime_type' => 'text/plain',
        'chars' => 13,
        'truncated' => false
      )
    end

    it 'uses embedded text from a PDF when enough text is present' do
      reader = instance_double(PDF::Reader, page_count: 1, pages: [double(text: 'embedded document text')])
      allow(Marcel::MimeType).to receive(:for).and_return('application/pdf')
      allow(PDF::Reader).to receive(:new).and_return(reader)

      result = described_class.call('%PDF content', filename: 'example.pdf')

      expect(result).to include('text' => 'embedded document text', 'method' => 'embedded', 'page_count' => 1)
    end

    it 'falls back to OCR when a PDF has insufficient embedded text' do
      reader = instance_double(PDF::Reader, page_count: 1, pages: [double(text: '')])
      allow(Marcel::MimeType).to receive(:for).and_return('application/pdf')
      allow(PDF::Reader).to receive(:new).and_return(reader)
      allow(described_class).to receive(:run_pdf_ocr).and_return('scanned document text')

      result = described_class.call('%PDF content', filename: 'scan.pdf')

      expect(result).to include('text' => 'scanned document text', 'method' => 'ocr', 'page_count' => 1)
    end

    it 'uses OCR for an image' do
      allow(Marcel::MimeType).to receive(:for).and_return('image/jpeg')
      allow(described_class).to receive(:run_ocr).and_return('image document text')

      result = described_class.call('image content', filename: 'scan.jpg')

      expect(result).to include('text' => 'image document text', 'method' => 'ocr', 'page_count' => 1)
    end

    it 'rejects a document larger than the configured limit' do
      expect do
        described_class.call('too large', filename: 'example.txt', maximum_file_size: 4)
      end.to raise_error(described_class::DocumentTooLarge, /maximum is 4/)
    end

    it 'rejects a PDF over the configured page limit' do
      reader = instance_double(PDF::Reader, page_count: 2)
      allow(Marcel::MimeType).to receive(:for).and_return('application/pdf')
      allow(PDF::Reader).to receive(:new).and_return(reader)

      expect do
        described_class.call('%PDF content', filename: 'example.pdf', maximum_pages: 1)
      end.to raise_error(described_class::PageLimitExceeded, /maximum is 1/)
    end

    it 'truncates extracted text and records the original character count' do
      result = described_class.call('long document', filename: 'example.txt', maximum_characters: 4)

      expect(result).to include(
        'text' => 'long',
        'chars' => 4,
        'original_chars' => 13,
        'truncated' => true
      )
    end

    it 'rejects unsupported document types' do
      allow(Marcel::MimeType).to receive(:for).and_return('application/zip')

      expect do
        described_class.call('archive content', filename: 'example.zip')
      end.to raise_error(described_class::UnsupportedDocument, %r{application/zip})
    end

    it 'rejects documents that produce no text' do
      reader = instance_double(PDF::Reader, page_count: 1, pages: [double(text: '')])
      allow(Marcel::MimeType).to receive(:for).and_return('application/pdf')
      allow(PDF::Reader).to receive(:new).and_return(reader)
      allow(described_class).to receive(:run_pdf_ocr).and_return('')

      expect do
        described_class.call('%PDF content', filename: 'empty.pdf')
      end.to raise_error(described_class::EmptyDocument, /produced no text/)
    end
  end
end
