# frozen_string_literal: true

require 'rails_helper'

RSpec.describe HCAAttachmentUploader, type: :uploader do
  let(:uploader) { described_class.new(guid) }

  let(:guid) { 'test-guid' }
  let(:file) do
    Rack::Test::UploadedFile.new(
      Rails.root.join('spec', 'fixtures', 'files', 'doctors-note.png'),
      'image/png'
    )
  end

  describe '#initialize' do
    context 'when Rails.env is production' do
      let(:settings) do
        OpenStruct.new(
          aws_access_key_id: 'access-key',
          aws_secret_access_key: 'shh-its-a-secret',
          region: 'my-region',
          bucket: 'bucket/path'
        )
      end

      before do
        allow(Settings).to receive(:hca).and_return(OpenStruct.new(s3: settings))
        allow(Rails.env).to receive(:production?).and_return(true)
      end

      it 'sets AWS config with production settings' do
        expect_any_instance_of(HCAAttachmentUploader).to receive(:set_aws_config).with(
          Settings.hca.s3.aws_access_key_id,
          Settings.hca.s3.aws_secret_access_key,
          Settings.hca.s3.region,
          Settings.hca.s3.bucket
        )

        described_class.new('test-guid')
      end
    end

    context 'when Rails.env is not production' do
      before do
        allow(Rails.env).to receive(:production?).and_return(false)
      end

      it 'does not set AWS config' do
        expect_any_instance_of(HCAAttachmentUploader).not_to receive(:set_aws_config)

        described_class.new('test-guid')
      end
    end
  end

  describe '#size_range' do
    it 'has a valid size range' do
      expect(uploader.size_range).to eq((1.byte)...(10.megabytes))
    end
  end

  describe '#extension_allowlist' do
    it 'allows valid file extensions including HEIC/HEIF' do
      expect(uploader.extension_allowlist).to include('pdf', 'doc', 'docx', 'jpg', 'jpeg', 'rtf', 'png', 'heic',
                                                      'heif')
    end

    it 'does not allow invalid file extensions' do
      expect(uploader.extension_allowlist).not_to include('exe', 'bat', 'zip')
    end
  end

  describe '#store_dir' do
    it 'sets the correct store directory' do
      expect(uploader.store_dir).to eq('hca_attachments')
    end
  end

  describe '#filename' do
    it 'sets the filename to the guid' do
      expect(uploader.filename).to eq(guid)
    end
  end

  describe 'processing' do
    it 'registers conditional processor for PNG, HEIC, and HEIF files' do
      expect(described_class.processors).to include([:convert_png_or_heic_to_jpg, [], nil, nil])
    end

    it 'converts a PNG file to jpg' do
      png_file = Rack::Test::UploadedFile.new(
        Rails.root.join('spec', 'fixtures', 'files', 'doctors-note.png'),
        'IMAGE/PNG'
      )

      image_processor = instance_double(MiniMagick::Image)
      expect(MiniMagick::Image).to receive(:new).and_return(image_processor)
      expect(image_processor).to receive(:format).with('jpg')

      uploader.store!(png_file)
    end

    it 'converts a HEIC file to jpg' do
      heic_file = Rack::Test::UploadedFile.new(
        Rails.root.join('spec', 'fixtures', 'files', 'steelers.heic'),
        'IMAGE/HEIC'
      )

      image_processor = instance_double(MiniMagick::Image)
      expect(MiniMagick::Image).to receive(:new).and_return(image_processor)
      expect(image_processor).to receive(:format).with('jpg')

      uploader.store!(heic_file)
    end

    it 'converts a HEIF file to jpg' do
      heif_file = Rack::Test::UploadedFile.new(
        Rails.root.join('spec', 'fixtures', 'files', 'steelers.heif'),
        'image/heif'
      )

      image_processor = instance_double(MiniMagick::Image)
      expect(MiniMagick::Image).to receive(:new).and_return(image_processor)
      expect(image_processor).to receive(:format).with('jpg')

      uploader.store!(heif_file)
    end

    it 'does not modify a PDF file' do
      pdf_file = Rack::Test::UploadedFile.new(
        Rails.root.join('spec', 'fixtures', 'files', 'doctors-note.pdf'),
        'application/pdf'
      )

      expect(MiniMagick::Image).not_to receive(:new)

      uploader.store!(pdf_file)
    end
  end
end
