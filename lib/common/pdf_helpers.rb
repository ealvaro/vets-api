# frozen_string_literal: true

require 'hexapdf'
require 'vets/shared_logging'
require 'logging/helper/data_scrubber'

module Common
  module PdfHelpers
    extend Vets::SharedLogging

    def self.unlock_pdf(input_file, password, output_file)
      doc = HexaPDF::Document.open(input_file, decryption_opts: { password: })
      doc.encrypt(name: nil)
      # Skip HexaPDF write-time validation: VA-provided PDFs contain AcroForm field names with literal
      # periods, which newer HexaPDF versions reject (`/T shall not contain a period`). Content
      # validation is handled separately by PDFUtilities::PDFValidator. Decryption/parse errors still
      # surface from HexaPDF::Document.open above.
      doc.write(output_file, validate: false)
    rescue HexaPDF::EncryptionError => e
      Rails.logger.warn(scrub_pii(e.message))
      raise Common::Exceptions::UnprocessableEntity.new(
        detail: I18n.t('errors.messages.uploads.pdf.incorrect_password'),
        source: 'Common::PdfHelpers.unlock_pdf'
      )
    rescue HexaPDF::Error => e
      Rails.logger.warn(scrub_pii(e.message))
      raise Common::Exceptions::UnprocessableEntity.new(
        detail: I18n.t('errors.messages.uploads.pdf.invalid'),
        source: 'Common::PdfHelpers.unlock_pdf'
      )
    end

    def self.scrub_pii(message)
      Logging::Helper::DataScrubber.scrub(message)
    end
    private_class_method :scrub_pii
  end
end
