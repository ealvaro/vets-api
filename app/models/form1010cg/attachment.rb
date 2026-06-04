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

    def unlock_pdf(file, file_password)
      tmpf = Tempfile.new(['decrypted_form1010cg_attachment', '.pdf'])
      begin
        Common::PdfHelpers.unlock_pdf(file.tempfile.path, file_password, tmpf.path)
      rescue Common::Exceptions::UnprocessableEntity => e
        tmpf.unlink
        handle_pdf_unlock_error(e)
      end
      file.tempfile.unlink
      file.tempfile = tmpf
      file
    end

    def handle_pdf_unlock_error(error)
      detail = error.errors&.first&.detail
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
