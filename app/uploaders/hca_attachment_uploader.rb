# frozen_string_literal: true

class HCAAttachmentUploader < CarrierWave::Uploader::Base
  include SetAWSConfig
  include UploaderVirusScan
  include CarrierWave::MiniMagick

  def size_range
    (1.byte)...(10.megabytes)
  end

  process(convert: 'jpg', if: :png?)
  process(convert: 'jpg', if: :heic?)

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

  def png?(file)
    file.content_type.to_s.downcase == 'image/png'
  end

  def heic?(file)
    file.content_type.to_s.downcase =~ %r{^image/(heic|heif)$}
  end
end
