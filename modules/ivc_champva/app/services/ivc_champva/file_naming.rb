# frozen_string_literal: true

module IvcChampva
  module FileNaming
    COMBINED_PDF_SUFFIX = '_combined.pdf'

    ##
    # Detects combined PDF files
    #
    # @param [String] filename The filename to check
    # @return [Boolean] true if the file is a combined PDF
    def self.combined_pdf?(filename)
      return false if filename.blank?

      filename.end_with?(COMBINED_PDF_SUFFIX)
    end
  end
end
