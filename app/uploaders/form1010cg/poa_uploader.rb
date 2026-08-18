# frozen_string_literal: true

module Form1010cg
  class PoaUploader < CarrierWave::Uploader::Base
    include SetAWSConfig
    include LogMetrics
    include UploaderVirusScan
    include CarrierWave::MiniMagick

    # NOTE: We intentionally avoid CarrierWave's conditional convert macro
    # (`process(convert: 'jpg', if: :heic?)`) due to intermittent behavior
    # observed with conditional processing callbacks. We perform an explicit,
    # deterministic conversion for HEIC/HEIF files in `normalize_heic_to_jpg`.
    # https://github.com/carrierwaveuploader/carrierwave/issues/2723
    process :normalize_heic_to_jpg

    storage :aws

    attr_reader :store_dir

    def initialize(form_attachment_guid)
      super

      set_aws_config(
        Settings.form_10_10cg.poa.s3.aws_access_key_id,
        Settings.form_10_10cg.poa.s3.aws_secret_access_key,
        Settings.form_10_10cg.poa.s3.region,
        Settings.form_10_10cg.poa.s3.bucket
      )

      @store_dir = form_attachment_guid
    end

    def extension_allowlist
      %w[jpg jpeg png pdf heic heif]
    end

    def content_type_allowlist
      %w[image/jpg image/jpeg image/png application/pdf image/heic image/heif]
    end

    def size_range
      (1.byte)...(10.megabytes)
    end

    private

    def normalize_heic_to_jpg
      return unless heic?(file)

      if Flipper.enabled?(:poa_upload_image_conversion_fix)
        Rails.logger.info(
          '[POA_CONVERT_ATTACHMENT] start',
          store_dir: @store_dir,
          ext: File.extname(file.file),
          content_type: file.content_type
        )
        manipulate! do |image|
          image.format('jpg')
          image
        end
      else
        converted_file = MiniMagick::Image.new(file.file)
        converted_file.format('jpg')

        file.content_type = 'image/jpeg' if file.respond_to?(:content_type=)
      end
    end

    def heic?(file)
      %w[image/heic image/heif].include? file.content_type.downcase
    end
  end
end
