# frozen_string_literal: true

require 'rails_helper'

RSpec.describe HCAAttachmentUploader, type: :uploader do
  let(:uploader) { described_class.new(guid) }
  let(:guid) { 'test-guid' }

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

      it 'sets AWS config with production settings' do
        allow(Settings).to receive(:hca).and_return(OpenStruct.new(s3: settings))
        allow(Rails.env).to receive(:production?).and_return(true)
        expect_any_instance_of(HCAAttachmentUploader).to receive(:set_aws_config).with(
          Settings.hca.s3.aws_access_key_id,
          Settings.hca.s3.aws_secret_access_key,
          Settings.hca.s3.region,
          Settings.hca.s3.bucket
        )

        described_class.new(guid)
      end
    end

    context 'when Rails.env is not production' do
      before do
        allow(Rails.env).to receive(:production?).and_return(false)
      end

      it 'does not set AWS config' do
        expect_any_instance_of(HCAAttachmentUploader).not_to receive(:set_aws_config)

        described_class.new(guid)
      end
    end
  end

  describe 'configuration' do
    describe '#size_range' do
      it 'has a valid size range' do
        expect(uploader.size_range).to eq((1.byte)...(10.megabytes))
      end
    end

    describe '#extension_allowlist' do
      it 'allows valid file extensions including HEIC/HEIF' do
        expect(
          uploader.extension_allowlist
        ).to contain_exactly('pdf', 'doc', 'docx', 'jpg', 'jpeg', 'rtf', 'png', 'heic', 'heif')
      end

      it 'does not allow invalid file extensions (intent-documentation spec)' do
        expect(uploader.extension_allowlist).not_to include('exe', 'bat', 'zip')
      end
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

    context 'when hca_upload_image_conversion_fix is disabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:hca_upload_image_conversion_fix).and_return(false)
      end

      it 'converts a PNG file to jpg' do
        png_file = Rack::Test::UploadedFile.new(
          Rails.root.join('spec', 'fixtures', 'files', 'doctors-note.png'),
          'IMAGE/PNG'
        )

        image_processor = instance_double(MiniMagick::Image)
        expect(MiniMagick::Image).to receive(:new).and_return(image_processor)
        expect(image_processor).to receive(:format).with('jpg')
        expect(Rails.logger).to receive(:info).with(
          '[HCA_CONVERT_ATTACHMENT] start', guid:, ext: '.png', content_type: 'image/png'
        )

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
        expect(Rails.logger).to receive(:info).with(
          '[HCA_CONVERT_ATTACHMENT] start', guid:, ext: '.heic', content_type: 'image/heic'
        )

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
        expect(Rails.logger).to receive(:info).with(
          '[HCA_CONVERT_ATTACHMENT] start', guid:, ext: '.heif', content_type: 'image/heic'
        )

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

    context 'when hca_upload_image_conversion_fix is enabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:hca_upload_image_conversion_fix).and_return(true)

        # Uploads live under a per-guid tmp dir during spec runs; clean up after each example.
        FileUtils.rm_rf(described_class.new(guid).cache_dir) if described_class.new(guid).respond_to?(:cache_dir)
      end

      after do
        uploader.remove! if uploader.file
      end

      context 'when the file is a PNG' do
        let(:png_file) do
          Rack::Test::UploadedFile.new(
            Rails.root.join('spec', 'fixtures', 'files', 'doctors-note.png'),
            'IMAGE/PNG'
          )
        end

        it 'converts the file to jpeg content type' do
          uploader.store!(png_file)

          expect(uploader.file.content_type).to eq('image/jpeg')
        end

        it 'does not leave the stored file path/key with a leaked .jpg extension' do
          uploader.store!(png_file)

          # This is the regression this spec exists to catch: MiniMagick#format
          # renames the underlying file on disk during conversion. If the
          # uploader's tracked `file` isn't repointed at the converted path,
          # CarrierWave stores under an unexpected key (e.g. "<guid>.jpg"
          # instead of "<guid>"), which later 404s on read from S3.
          expect(uploader.filename).to eq(guid)
          expect(File.basename(uploader.file.path)).not_to end_with('.jpg')
        end

        it 'is a valid, readable jpeg after conversion' do
          uploader.store!(png_file)

          identify_output = MiniMagick::Image.new(uploader.file.path).type
          expect(identify_output.downcase).to eq('jpeg')
        end

        it 'converts the file to jpg when MIME type casing varies' do
          uppercase_mime_file = Rack::Test::UploadedFile.new(
            Rails.root.join('spec', 'fixtures', 'files', 'doctors-note.png'),
            'IMAGE/PNG'
          )

          uploader.store!(uppercase_mime_file)

          expect(uploader.file.content_type).to eq('image/jpeg')
        end
      end

      context 'when the file is a HEIC' do
        let(:heic_file) do
          Rack::Test::UploadedFile.new(
            Rails.root.join('spec', 'fixtures', 'files', 'steelers.heic'),
            'IMAGE/HEIC'
          )
        end

        it 'converts the file to jpeg content type' do
          uploader.store!(heic_file)

          expect(uploader.file.content_type).to eq('image/jpeg')
        end

        it 'does not leave the stored file path/key with a leaked .jpg extension' do
          uploader.store!(heic_file)

          expect(uploader.filename).to eq(guid)
          expect(File.basename(uploader.file.path)).not_to end_with('.jpg')
        end

        it 'is a valid, readable jpeg after conversion' do
          uploader.store!(heic_file)

          identify_output = MiniMagick::Image.new(uploader.file.path).type
          expect(identify_output.downcase).to eq('jpeg')
        end
      end

      context 'when the file is a HEIF' do
        let(:heif_file) do
          Rack::Test::UploadedFile.new(
            Rails.root.join('spec', 'fixtures', 'files', 'steelers.heif'),
            'IMAGE/HEIF'
          )
        end

        it 'converts the file to jpeg content type' do
          uploader.store!(heif_file)

          expect(uploader.file.content_type).to eq('image/jpeg')
        end

        it 'does not leave the stored file path/key with a leaked .jpg extension' do
          uploader.store!(heif_file)

          expect(uploader.filename).to eq(guid)
          expect(File.basename(uploader.file.path)).not_to end_with('.jpg')
        end
      end

      context 'when the file is a PDF' do
        let(:pdf_file) do
          Rack::Test::UploadedFile.new(
            Rails.root.join('spec', 'fixtures', 'files', 'doctors-note.pdf'),
            'application/pdf'
          )
        end

        it 'does not modify a PDF file' do
          expect(MiniMagick::Image).not_to receive(:new)

          uploader.store!(pdf_file)
        end

        it 'stores the file under the guid filename, unmodified' do
          uploader.store!(pdf_file)

          expect(uploader.filename).to eq(guid)
          expect(File.extname(uploader.file.path)).to be_blank
        end
      end
    end
  end
end
