# frozen_string_literal: true

class HCAAttachmentUploader < CarrierWave::Uploader::Base
  include SetAWSConfig
  include UploaderVirusScan
  include CarrierWave::MiniMagick

  def size_range
    (1.byte)...(10.megabytes)
  end

  # NOTE: We intentionally avoid CarrierWave's conditional convert macro
  # (`process(convert: 'jpg', if: :heic?)`) due to intermittent behavior
  # observed with conditional processing callbacks. We perform an explicit,
  # deterministic conversion for HEIC/HEIF files in `convert_png_or_heic_to_jpg`.
  # https://github.com/carrierwaveuploader/carrierwave/issues/2723
  process :convert_png_or_heic_to_jpg

  def initialize(guid)
    super
    @guid = guid

    if Rails.env.production?
      set_aws_config(
        Settings.hca.s3.aws_access_key_id,
        Settings.hca.s3.aws_secret_access_key,
        Settings.hca.s3.region,
        Settings.hca.s3.bucket
      )
    end
  end

  # accepted by enrollment system: PDF, WORD, JPG, RTF
  # (HEIC/HEIF uploads are accepted and converted to JPG).
  def extension_allowlist
    %w[pdf doc docx jpg jpeg rtf png heic heif]
  end

  def store_dir
    'hca_attachments'
  end

  def filename
    @guid
  end

  private

  def convert_png_or_heic_to_jpg
    return unless png_or_heic?(file)

    Rails.logger.info(
      '[HCA_CONVERT_ATTACHMENT] start',
      guid: filename,
      ext: File.extname(file.file),
      content_type: file.content_type
    )
    if Flipper.enabled?(:hca_upload_image_conversion_fix)
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

  def png_or_heic?(file)
    %w[image/png image/heic image/heif].include? file.content_type.downcase
  end
end
