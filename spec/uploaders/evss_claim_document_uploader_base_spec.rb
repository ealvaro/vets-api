# frozen_string_literal: true

require 'rails_helper'

describe EVSSClaimDocumentUploaderBase, :uploader_helpers do
  def store_image
    EVSSClaimDocumentUploaderBase.new.store!(file)
  end

  describe 'configured size limits' do
    let(:uploader) { described_class.new }

    it 'allows non-PDF files up to 100 megabytes' do
      expect(uploader.max_file_size_non_pdf).to eq(100.megabytes)
    end

    it 'permits files just under 100 megabytes in size_range' do
      expect(uploader.size_range).to eq((1.byte)...(100.megabytes))
    end
  end

  context 'with a too large file that is not a PDF' do
    before do
      allow_any_instance_of(described_class).to receive(:max_file_size_non_pdf).and_return(100)
    end

    let(:file) { Rack::Test::UploadedFile.new('spec/fixtures/files/va.gif', 'image/gif') }

    it 'raises an error' do
      expect { store_image }.to raise_error CarrierWave::IntegrityError
    end
  end

  context 'with a valid PDF' do
    let(:file) { Rack::Test::UploadedFile.new('spec/fixtures/files/doctors-note.pdf', 'application/pdf') }

    it 'does not raise an error' do
      expect { store_image }.not_to raise_error
    end
  end
end
