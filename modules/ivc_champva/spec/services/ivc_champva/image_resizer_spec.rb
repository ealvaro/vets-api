# frozen_string_literal: true

require 'rails_helper'

RSpec.describe IvcChampva::ImageResizer do
  def uploaded_file(name, type)
    ActionDispatch::Http::UploadedFile.new(
      tempfile: Rails.root.join('spec', 'fixtures', 'files', name).open('rb'),
      filename: name,
      type:
    )
  end

  let(:oversized_image) { uploaded_file('oversized-image.png', 'image/png') }
  let(:within_bounds_image) { uploaded_file('doctors-note.png', 'image/png') }
  let(:pdf_file) { uploaded_file('doctors-note.pdf', 'application/pdf') }
  # A raw Tempfile mimics what unlock_file hands back for a decrypted PDF: it
  # has no #content_type / #original_filename.
  let(:bare_tempfile) do
    tempfile = Tempfile.new(['decrypted', '.pdf'])
    tempfile.binmode
    tempfile.write(Rails.root.join('spec', 'fixtures', 'files', 'doctors-note.pdf').binread)
    tempfile.rewind
    tempfile
  end

  describe '#content_type' do
    it 'returns nil for an input that does not report a content type' do
      expect(described_class.new(bare_tempfile).content_type).to be_nil
    end
  end

  describe '#valid?' do
    it 'is false for an image that exceeds the uploader dimension limits' do
      expect(described_class.new(oversized_image).valid?).to be(false)
    end

    it 'is true for an image within the uploader dimension limits' do
      expect(described_class.new(within_bounds_image).valid?).to be(true)
    end

    it 'is true for a non-image file (e.g. PDF), which is never resized' do
      expect(described_class.new(pdf_file).valid?).to be(true)
    end

    it 'is true (never raises) for an input without a content type (decrypted PDF Tempfile)' do
      expect(described_class.new(bare_tempfile).valid?).to be(true)
    end

    it 'is true when dimensions cannot be determined' do
      resizer = described_class.new(oversized_image)
      allow(resizer).to receive(:original_dimensions).and_return([nil, nil])
      expect(resizer.valid?).to be(true)
    end
  end

  describe '#resize' do
    it 'downscales to within the uploader bounds while preserving filename and content type' do
      resized = described_class.new(oversized_image).resize

      expect(resized).to be_a(ActionDispatch::Http::UploadedFile)
      expect(resized.original_filename).to eq('oversized-image.png')
      expect(resized.content_type).to eq('image/png')

      width, height = MiniMagick::Image.open(resized.tempfile.path).dimensions
      expect(width).to be <= ClaimDocumentation::Uploader::MAX_IMAGE_WIDTH
      expect(height).to be <= ClaimDocumentation::Uploader::MAX_IMAGE_HEIGHT
    end

    it 'preserves aspect ratio when downscaling' do
      original_width, original_height = described_class.new(oversized_image).original_dimensions
      resized = described_class.new(oversized_image).resize
      new_width, new_height = MiniMagick::Image.open(resized.tempfile.path).dimensions

      expect(new_width.to_f / new_height).to be_within(0.01).of(original_width.to_f / original_height)
    end

    it 'raises when MiniMagick fails so the caller can handle the fallback' do
      allow(MiniMagick::Image).to receive(:open).and_raise(MiniMagick::Error.new('boom'))
      expect { described_class.new(oversized_image).resize }.to raise_error(MiniMagick::Error)
    end
  end

  describe '#original_dimensions' do
    it 'returns the [width, height] for an image' do
      expect(described_class.new(oversized_image).original_dimensions).to eq([6000, 8000])
    end

    it 'returns [nil, nil] for a non-image file' do
      expect(described_class.new(pdf_file).original_dimensions).to eq([nil, nil])
    end

    it 'returns [nil, nil] when MiniMagick cannot read the image' do
      allow(MiniMagick::Image).to receive(:open).and_raise(MiniMagick::Error.new('boom'))
      expect(described_class.new(oversized_image).original_dimensions).to eq([nil, nil])
    end
  end
end
