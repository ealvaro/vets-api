# frozen_string_literal: true

require 'common/pdf_helpers'

module Form1010cg
  class Attachment < FormAttachment
    ATTACHMENT_UPLOADER_CLASS = ::Form1010cg::PoaUploader

    def to_local_file
      remote_file = get_file
      local_path  = "tmp/#{remote_file.path.gsub('/', '_')}"

      File.write(local_path, remote_file.read)

      local_path
    end

    private

    def unlock_with_hexapdf(source_file, file_password, destination_file)
      Common::PdfHelpers.unlock_pdf(source_file.tempfile.path, file_password, destination_file.path)
      destination_file.rewind
    rescue Common::Exceptions::UnprocessableEntity => e
      # Shared unlock behavior is already deduplicated in FormAttachment; this
      # override keeps 10-10CG's error contract (safe_detail + form-specific logs).
      detail = e.errors&.first&.detail
      if detail == I18n.t('errors.messages.uploads.pdf.incorrect_password')
        Rails.logger.warn('[Form 10-10CG] PDF unlock failed: incorrect password provided')
        safe_detail = I18n.t('errors.messages.uploads.pdf.incorrect_password')
      else
        Rails.logger.warn('[Form 10-10CG] PDF unlock failed: invalid pdf provided')
        safe_detail = I18n.t('errors.messages.uploads.pdf.invalid')
      end

      raise Common::Exceptions::UnprocessableEntity.new(
        detail: safe_detail,
        source: 'Common::PdfHelpers.unlock_pdf'
      ), cause: nil
    end
  end
end
