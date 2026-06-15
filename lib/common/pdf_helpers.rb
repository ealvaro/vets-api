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
      doc.write(output_file)
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
