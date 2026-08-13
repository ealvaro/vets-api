# frozen_string_literal: true

module IvcChampva
  class PdfCombiner
    # Generic utility to combine multiple PDFs into a single PDF, maintaining
    # the order of the original files

    # @param merged_pdf_path [String] The path of the output file
    # @param file_paths [Array<String>] The paths to the PDFs to combine
    # @return [String] The path to the combined PDF
    def self.combine(merged_pdf_path, file_paths)
      return merged_pdf_path if file_paths.empty?

      combine_using_hexapdf(merged_pdf_path, file_paths)
    end

    # Alternative PDF combiner using HexaPDF instead of CombinePDF.
    #
    # @param merged_pdf_path [String] The path of the output file
    # @param file_paths [Array<String>] The paths to the PDFs to combine
    # @return [String] The path to the combined PDF
    def self.combine_using_hexapdf(merged_pdf_path, file_paths)
      # Create a new empty HexaPDF document to hold the combined pages
      target = HexaPDF::Document.new

      file_paths.each_with_index do |file_path, index|
        # Open each source PDF
        source = HexaPDF::Document.open(file_path)

        # Import each page from the source into the target document
        source.pages.each do |page|
          target.pages << target.import(page)
        end
      rescue SystemCallError => e # Base class for any filesystem related errors
        # e.message could contain a filename and PII, so only pass on the decoded error number when available
        error_name = Errno.constants.find(proc {
          "Unknown #{e.errno}"
        }) { |c| Errno.const_get(c).new.errno == e.errno }.to_s
        Rails.logger.error("Error merging file at index #{index}: SystemCallError #{error_name}")
        raise
      rescue => e
        Rails.logger.error("Error merging file at index #{index}: #{e.message}")
        raise
      end

      # Write the combined document to the output path
      # Do not perform validation, we want to merge the files as-is and not fail on minor issues
      target.write(merged_pdf_path, optimize: true, validate: false)

      merged_pdf_path
    end
  end
end
