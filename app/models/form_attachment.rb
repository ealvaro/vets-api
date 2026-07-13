# frozen_string_literal: true

require 'common/pdf_helpers'

class FormAttachment < ApplicationRecord
  include SetGuid

  INCORRECT_PASSWORD_ERROR_MESSAGE = 'The password you entered is incorrect. Please try again.'

  has_kms_key
  has_encrypted :file_data, key: :kms_key, **lockbox_options

  validates(:file_data, :guid, presence: true)

  before_destroy { |record| record.get_file.delete }

  # Processes and stores an uploaded file. If the file is a password-protected PDF,
  # it will be decrypted before storage.
  #
  # @param file [ActionDispatch::Http::UploadedFile, Rack::Test::UploadedFile] the uploaded PDF or document file
  # @param file_password [String, nil] optional password to unlock an encrypted PDF
  # @return [void]
  # @raise [Common::Exceptions::UnprocessableEntity] if a virus is detected, the file fails
  #   integrity checks, or the PDF cannot be unlocked
  def set_file_data!(file, file_password = nil)
    attachment_uploader = get_attachment_uploader
    file = unlock_pdf(file, file_password) if !file_password.nil? && File.extname(file).downcase == '.pdf'

    attachment_uploader.store!(file)
    self.file_data = { filename: attachment_uploader.filename }.to_json

    log_s3_key = redacted_s3_key_for_log(attachment_uploader.store_dir, attachment_uploader.filename)

    Rails.logger.info(
      '[HCA_S3_WRITE] S3 object written | ' \
      "correlation_id=#{guid} | " \
      "s3_key=#{log_s3_key}"
    )

    file_data
  rescue UploaderVirusScan::VirusFoundError
    Rails.logger.warn("#{self.class.name}#set_file_data!: virus detected in upload")
    raise Common::Exceptions::UnprocessableEntity.new(
      detail: 'We were unable to process your file. Please try again.',
      source: 'FormAttachment.set_file_data'
    )
  rescue CarrierWave::IntegrityError => e
    Rails.logger.warn("FormAttachment.set_file_data error: #{e.message}")
    raise Common::Exceptions::UnprocessableEntity.new(detail: e.message, source: 'FormAttachment.set_file_data')
  end

  def parsed_file_data
    @parsed_file_data ||= JSON.parse(file_data)
  end

  def get_file
    attachment_uploader = get_attachment_uploader
    filename = parsed_file_data['filename']
    log_s3_key = redacted_s3_key_for_log(attachment_uploader.store_dir, filename)

    attachment_uploader.retrieve_from_store!(filename)
    Rails.logger.info(
      '[HCA_S3_READ] S3 object retrieved | ' \
      "correlation_id=#{guid} | " \
      "s3_key=#{log_s3_key}"
    )
    attachment_uploader.file
  rescue => e
    Rails.logger.error(
      '[HCA_S3_READ_FAILURE] S3 object retrieval failed | ' \
      "correlation_id=#{guid} | " \
      "s3_key=#{log_s3_key}",
      exception: e
    )
    raise
  end

  private

  def unlock_pdf(file, file_password)
    tmpf = Tempfile.new(['decrypted_form_attachment', '.pdf'])

    unlock_with_hexapdf(file, file_password, tmpf)

    file.tempfile.unlink
    # Replace the underlying tempfile using instance_variable_set since
    # Rack::Test::UploadedFile only provides a reader for :tempfile
    file.instance_variable_set(:@tempfile, tmpf)
    file
  end

  def unlock_with_hexapdf(source_file, file_password, destination_file)
    Common::PdfHelpers.unlock_pdf(source_file.tempfile.path, file_password, destination_file.path)
    destination_file.rewind
  rescue Common::Exceptions::UnprocessableEntity => e
    error_detail = e.errors.first&.detail

    if error_detail == I18n.t('errors.messages.uploads.pdf.incorrect_password')
      # HexaPDF avoids shelling out with password args, so we log a fixed message
      # instead of sanitizing command output with regexes.
      Rails.logger.warn('FormAttachment.unlock_pdf error: incorrect password provided')
      raise Common::Exceptions::UnprocessableEntity.new(
        detail: INCORRECT_PASSWORD_ERROR_MESSAGE,
        source: 'FormAttachment.unlock_pdf'
      ), cause: nil
    end

    Rails.logger.warn('FormAttachment.unlock_pdf error: invalid pdf provided')
    raise Common::Exceptions::UnprocessableEntity.new(
      detail: error_detail || I18n.t('errors.messages.uploads.pdf.invalid'),
      source: 'FormAttachment.unlock_pdf'
    ), cause: nil
  end

  def get_attachment_uploader
    @au ||= self.class::ATTACHMENT_UPLOADER_CLASS.new(guid)
  end

  def redacted_s3_key_for_log(store_dir, filename)
    return "#{store_dir}/#{filename}" if filename.to_s == guid.to_s

    "#{store_dir}/[REDACTED]"
  end
end
