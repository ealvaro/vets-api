# frozen_string_literal: true

require 'common/pdf_helpers'
require 'pdf_utilities/pdf_validator'

module ClaimsEvidence
  # Decrypts an encrypted PDF in place with the password the Veteran supplied; non-PDFs and
  # PDFs that open on their own pass through untouched. The password lives only here, never
  # on UploadRequest, whose Data#inspect would print it into any log line that touches it.
  class PdfUnlocker
    # Carries a code, not a sentence: the frontend keys off the detail string.
    class Rejected < StandardError
      attr_reader :code, :reason

      def initialize(reason:, code:)
        @reason = reason
        @code = code
        super(code)
      end
    end

    # The only override of PDFValidator's defaults. It checks pages against 21x21in unless
    # told not to, and Claims Evidence documents no such limit in their OpenAPI spec, so
    # we'll set it to false.
    VALIDATOR_OPTIONS = { check_page_dimensions: false }.freeze

    ENCRYPTION_MESSAGES = [
      PDFUtilities::PDFValidator::USER_PASSWORD_MSG,
      PDFUtilities::PDFValidator::OWNER_PASSWORD_MSG
    ].freeze

    # @param file [Tempfile] the upload copy, rewritten in place when decrypted
    # @param file_name [String] the Veteran's filename, used only to spot PDFs
    # @param password [String, nil] supplied only for encrypted PDFs
    def initialize(file, file_name, password: nil)
      @file = file
      @file_name = file_name
      @password = password.to_s
    end

    # Leaves @file holding the bytes to upload.
    # @raise [Rejected] when the PDF can't be uploaded as it stands
    def unlock!
      return unless pdf?

      result = PDFUtilities::PDFValidator::Validator.new(@file.path, VALIDATOR_OPTIONS).validate
      return if result.valid_pdf?
      raise Rejected.new(reason: 'invalid_pdf', code: 'DOC_UPLOAD_INVALID_PDF') unless encrypted?(result)

      decrypt_in_place
    end

    private

    def pdf?
      File.extname(@file_name).casecmp?('.pdf')
    end

    def encrypted?(result)
      result.errors.intersect?(ENCRYPTION_MESSAGES)
    end

    def decrypt_in_place
      Tempfile.create(['claims-evidence-decrypted', '.pdf']) do |decrypted|
        decrypted.binmode
        unlock(decrypted)
        overwrite_source(decrypted)
      end
    end

    # Tries the empty password rather than rejecting outright: that opens an owner-password
    # PDF, and otherwise lands on DOC_UPLOAD_ENCRYPTED_PDF below.
    def unlock(decrypted)
      ::Common::PdfHelpers.unlock_pdf(@file.path, @password, decrypted.path)
    rescue Common::Exceptions::UnprocessableEntity => e
      # cause: nil keeps the original error — raised while the password was in scope — out of
      # this one's chain. PdfHelpers already logged a scrubbed message.
      raise rejection_for(e), cause: nil
    end

    def rejection_for(error)
      unless error.errors.first&.detail == I18n.t('errors.messages.uploads.pdf.incorrect_password')
        return Rejected.new(reason: 'invalid_pdf', code: 'DOC_UPLOAD_INVALID_PDF')
      end

      if @password.blank?
        Rejected.new(reason: 'encrypted_pdf', code: 'DOC_UPLOAD_ENCRYPTED_PDF')
      else
        Rejected.new(reason: 'incorrect_password', code: 'DOC_UPLOAD_INCORRECT_PASSWORD')
      end
    end

    # The caller uploads @file, so the decrypted bytes have to land there. Copying back rather
    # than swapping handles leaves each tempfile to be unlinked by the block that made it.
    def overwrite_source(decrypted)
      decrypted.rewind
      @file.truncate(0)
      @file.rewind
      IO.copy_stream(decrypted, @file)
      @file.flush
    end
  end
end
