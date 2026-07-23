# frozen_string_literal: true

module IvcChampva
  module FileNaming
    COMBINED_PDF_SUFFIX = '_combined.pdf'

    # Matches VES JSON files: the 10-10D "_ves.json" and the indexed OHI
    # "_ohi_ves_N.json". These are ingested by VES, not tracked by Pega, so they
    # must be excluded from DB persistence and Pega status reconciliation.
    VES_JSON_REGEX = /_(?:ohi_)?ves(?:_\d+)?\.json\z/

    ##
    # Detects combined PDF files
    #
    # @param [String] filename The filename to check
    # @return [Boolean] true if the file is a combined PDF
    def self.combined_pdf?(filename)
      return false if filename.blank?

      filename.end_with?(COMBINED_PDF_SUFFIX)
    end

    ##
    # Detects VES JSON files (10-10D "_ves.json" and OHI "_ohi_ves_N.json")
    #
    # @param [String] filename The filename to check
    # @return [Boolean] true if the file is a VES JSON file
    def self.ves_json?(filename)
      return false if filename.blank?

      filename.match?(VES_JSON_REGEX)
    end
  end
end
