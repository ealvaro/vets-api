# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Form1010EzrAttachments::ImageResizer do
  def uploaded_file(name, mime_type)
    ActionDispatch::Http::UploadedFile.new(
      tempfile: Rails.root.join('spec', 'fixtures', 'files', name).open('rb'),
      filename: name,
      type: mime_type
    )
  end

  let(:oversized_image) { uploaded_file('oversized-image.png', 'image/png') }
  let(:within_bounds_image) { uploaded_file('doctors-note.png', 'image/png') }
  let(:pdf_file) { uploaded_file('doctors-note.pdf', 'application/pdf') }
  let(:bare_tempfile) do
    tempfile = Tempfile.new(['decrypted', '.pdf'])
    tempfile.binmode
    tempfile.write(Rails.root.join('spec', 'fixtures', 'files', 'doctors-note.pdf').binread)
    tempfile.rewind
    tempfile
  end
  let(:path_only_file) do
    Struct.new(:content_type, :original_filename, :path).new(
      'image/png',
      'oversized-image.png',
      Rails.root.join('spec', 'fixtures', 'files', 'oversized-image.png').to_s
    )
  end
  let(:tempfile_nil_file) do
    Struct.new(:content_type, :original_filename, :tempfile, :path).new(
      'image/png',
      'oversized-image.png',
      nil,
      Rails.root.join('spec', 'fixtures', 'files', 'oversized-image.png').to_s
    )
  end
  let(:path_only_non_image_file) do
    Struct.new(:content_type, :original_filename, :path).new(
      'application/pdf',
      'doctors-note.pdf',
      Rails.root.join('spec', 'fixtures', 'files', 'doctors-note.pdf').to_s
    )
  end

  describe '#content_type' do
    it 'returns nil for an input that does not report a content type' do
      expect(described_class.new(bare_tempfile).content_type).to be_nil
    end
  end

  describe '#valid?' do
    it 'is false for an image that exceeds the dimension limits' do
      expect(described_class.new(oversized_image).valid?).to be(false)
    end

    it 'is true for an image within the dimension limits' do
      expect(described_class.new(within_bounds_image).valid?).to be(true)
    end

    it 'is true for a non-image file (e.g. PDF), which is never resized' do
      expect(described_class.new(pdf_file).valid?).to be(true)
    end

    it 'is true when the dimensions cannot be determined' do
      resizer = described_class.new(oversized_image)
      allow(resizer).to receive(:original_dimensions).and_return([nil, nil])
      expect(resizer.valid?).to be(true)
    end
  end

  describe '#resize' do
    it 'downscales the image to fit within the dimension bounds and preserves format/filename' do
      resized = described_class.new(oversized_image).resize

      expect(resized).to be_a(ActionDispatch::Http::UploadedFile)
      expect(resized.original_filename).to eq('oversized-image.png')
      expect(resized.content_type).to eq('image/png')

      width, height = MiniMagick::Image.open(resized.tempfile.path).dimensions
      expect(width).to be <= described_class::MAX_WIDTH
      expect(height).to be <= described_class::MAX_HEIGHT
    end

    it 'preserves aspect ratio' do
      original_width, original_height = described_class.new(oversized_image).original_dimensions
      resized = described_class.new(oversized_image).resize
      new_width, new_height = MiniMagick::Image.open(resized.tempfile.path).dimensions

      expect((new_width.to_f / new_height).round(2)).to eq((original_width.to_f / original_height).round(2))
    end

    it 'raises when MiniMagick fails so the caller can handle the fallback' do
      allow(MiniMagick::Image).to receive(:open).and_raise(MiniMagick::Error.new('boom'))
      expect { described_class.new(oversized_image).resize }.to raise_error(MiniMagick::Error)
    end

    it 'can resize an image object that only exposes #path (no #tempfile)' do
      resized = described_class.new(path_only_file).resize

      expect(resized).to be_a(ActionDispatch::Http::UploadedFile)
      width, height = MiniMagick::Image.open(resized.tempfile.path).dimensions
      expect(width).to be <= described_class::MAX_WIDTH
      expect(height).to be <= described_class::MAX_HEIGHT
    end

    it 'falls back to #path when #tempfile is present but nil' do
      resized = described_class.new(tempfile_nil_file).resize

      expect(resized).to be_a(ActionDispatch::Http::UploadedFile)
      width, height = MiniMagick::Image.open(resized.tempfile.path).dimensions
      expect(width).to be <= described_class::MAX_WIDTH
      expect(height).to be <= described_class::MAX_HEIGHT
    end
  end

  describe '#original_dimensions' do
    it 'returns the dimensions of an image' do
      expect(described_class.new(oversized_image).original_dimensions).to eq([6000, 8000])
    end

    it 'returns [nil, nil] when MiniMagick cannot read the image' do
      allow(MiniMagick::Image).to receive(:open).and_raise(MiniMagick::Error.new('boom'))
      expect(described_class.new(oversized_image).original_dimensions).to eq([nil, nil])
    end

    it 'returns [nil, nil] for a path-only non-image file' do
      expect(described_class.new(path_only_non_image_file).original_dimensions).to eq([nil, nil])
    end
  end
end
