# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Form1010EzrAttachments::ImageResizeService do
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

  before do
    allow(StatsD).to receive(:increment)
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:warn)
  end

  describe '#resize_if_needed' do
    it 'downscales an oversized image and logs/increments a resized outcome' do
      result = described_class.new(oversized_image).resize_if_needed

      expect(result).not_to eq(oversized_image)
      width, height = MiniMagick::Image.open(result.tempfile.path).dimensions
      expect(width).to be <= Form1010EzrAttachments::ImageResizer::MAX_WIDTH
      expect(height).to be <= Form1010EzrAttachments::ImageResizer::MAX_HEIGHT

      expect(StatsD).to have_received(:increment).with('api.1010ezr.attachments.image_resize.resized')
      expect(Rails.logger).to have_received(:info).with(
        '[Form1010EzrAttachments] image resize resized',
        hash_including(original_width: 6000, original_height: 8000, content_type: 'image/png')
      )
    end

    it 'returns the original file and does not log when the image is already within bounds' do
      service = described_class.new(within_bounds_image)

      expect(service.resize_if_needed).to eq(within_bounds_image)
      expect(StatsD).not_to have_received(:increment)
    end

    it 'returns non-image files untouched and does not log' do
      service = described_class.new(pdf_file)

      expect(service.resize_if_needed).to eq(pdf_file)
      expect(StatsD).not_to have_received(:increment)
    end

    it 'falls back to the original file and logs an error outcome when resizing fails' do
      allow_any_instance_of(Form1010EzrAttachments::ImageResizer)
        .to receive(:resize).and_raise(MiniMagick::Error.new('boom'))

      service = described_class.new(oversized_image)

      expect(service.resize_if_needed).to eq(oversized_image)
      expect(StatsD).to have_received(:increment).with('api.1010ezr.attachments.image_resize.error')
      expect(Rails.logger).to have_received(:warn).with(
        '[Form1010EzrAttachments] image resize error',
        hash_including(error_class: 'MiniMagick::Error', content_type: 'image/png')
      )
    end
  end
end
