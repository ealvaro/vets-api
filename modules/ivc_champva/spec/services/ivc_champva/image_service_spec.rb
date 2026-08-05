# frozen_string_literal: true

require 'rails_helper'
require_relative '../../../lib/ivc_champva/monitor'

RSpec.describe IvcChampva::ImageService do
  def uploaded_file(name, type)
    ActionDispatch::Http::UploadedFile.new(
      tempfile: Rails.root.join('spec', 'fixtures', 'files', name).open('rb'),
      filename: name,
      type:
    )
  end

  let(:monitor) { instance_spy(IvcChampva::Monitor) }
  let(:oversized_image) { uploaded_file('oversized-image.png', 'image/png') }
  let(:within_bounds_image) { uploaded_file('doctors-note.png', 'image/png') }
  let(:pdf_file) { uploaded_file('doctors-note.pdf', 'application/pdf') }

  describe '#resize_if_needed' do
    it 'downscales an oversized image and logs a resized decision with context' do
      result = described_class.new(oversized_image, '10-10D', monitor:).resize_if_needed

      expect(result).not_to eq(oversized_image)
      width, height = MiniMagick::Image.open(result.tempfile.path).dimensions
      expect(width).to be <= ClaimDocumentation::Uploader::MAX_IMAGE_WIDTH
      expect(height).to be <= ClaimDocumentation::Uploader::MAX_IMAGE_HEIGHT
      expect(monitor).to have_received(:track_image_resize)
        .with('10-10D', 'resized',
              hash_including(original_width: 6000, original_height: 8000, content_type: 'image/png'))
    end

    it 'returns the original file and does not log when the image is already within bounds' do
      service = described_class.new(within_bounds_image, '10-10D', monitor:)

      expect(service.resize_if_needed).to eq(within_bounds_image)
      expect(monitor).not_to have_received(:track_image_resize)
    end

    it 'returns non-image files untouched and does not log' do
      service = described_class.new(pdf_file, '10-10D', monitor:)

      expect(service.resize_if_needed).to eq(pdf_file)
      expect(monitor).not_to have_received(:track_image_resize)
    end

    it 'returns an input without a content type (decrypted PDF Tempfile) untouched and does not log' do
      tempfile = Tempfile.new(['decrypted', '.pdf'])
      tempfile.binmode
      tempfile.write(Rails.root.join('spec', 'fixtures', 'files', 'doctors-note.pdf').binread)
      tempfile.rewind

      service = described_class.new(tempfile, '10-10D', monitor:)

      expect(service.resize_if_needed).to eq(tempfile)
      expect(monitor).not_to have_received(:track_image_resize)
    end

    it 'falls back to the original file and logs an error when resizing fails' do
      allow_any_instance_of(IvcChampva::ImageResizer)
        .to receive(:resize).and_raise(MiniMagick::Error.new('boom'))

      service = described_class.new(oversized_image, '10-10D', monitor:)

      expect(service.resize_if_needed).to eq(oversized_image)
      expect(monitor).to have_received(:track_image_resize)
        .with('10-10D', 'error', hash_including(error_class: 'MiniMagick::Error', content_type: 'image/png'))
    end
  end
end
