# frozen_string_literal: true

require 'common/file_helpers'
require 'pdf_utilities/exception_handling'
require 'hexapdf'
require 'hexapdf/cli'

# Utility classes and functions for VA PDF
module PDFUtilities
  # @see https://github.com/jkraemer/pdf-forms
  PDFTK = PdfForms.new(Settings.binaries.pdftk)

  # add a watermark datestamp to an existing pdf
  class DatestampPdf
    include PDFUtilities::ExceptionHandling

    # metric stat key
    STATS_KEY = 'api.datestamp_pdf.error'
    # metric stat key for successful fallback to HexaPDF after a pdftk failure
    PDFTK_FALLBACK_STATS_KEY = 'api.datestamp_pdf.pdftk_fallback'

    # prepare to datestamp an existing pdf document
    #
    # @param file_path [String] path to the PDF file
    # @param append_to_stamp [String, nil] text to append to the stamp
    # @raise [PdfMissingError] if the PDF file doesn't exist
    #
    def initialize(file_path, append_to_stamp: nil)
      @file_path = file_path
      @append_to_stamp = append_to_stamp

      raise PdfMissingError, 'Original PDF is missing' unless File.exist?(file_path)
    rescue => e
      log_and_raise_error('Failed to initialize DatestampPdf', e, STATS_KEY)
    end

    # create a datestamped pdf copy of `file_path`
    #
    # @param settings [Hash] options for generating the datestamp
    # @option settings [String] :text the stamp text
    # @option settings [Integer] :x stamp x coordinate; default 5
    # @option settings [Integer] :y stamp y coordinate; default 5
    # @option settings [Boolean] :text_only only stamp the provided text, no timestamp; default false
    # @option settings [Integer] :size font size; default 10
    # @option settings [Time] :timestamp the timestamp to include; default Time.zone.now
    # @option settings [Integer, nil] :page_number on which page to place the stamp; default nil
    # @option settings [String, nil] :template another pdf on which to base the stamped pdf; default nil
    # @option settings [Boolean] :multistamp apply stamped pdf page to corresponding input pdf; default false
    #
    # @return [String] path to generated stamped pdf
    #
    def run(settings)
      settings = default_settings.merge(settings)
      settings.each { |key, value| instance_variable_set("@#{key}", value) }

      generate_stamp
      stamp_pdf
    rescue => e
      Common::FileHelpers.delete_file_if_exists(stamped_pdf)
      log_and_raise_error('Failed to generate datestamp file', e, STATS_KEY)
    ensure
      Common::FileHelpers.delete_file_if_exists(stamp_path)
    end

    private

    attr_reader :text, :x, :y, :text_only, :size, :page_number, :template, :multistamp, :file_path, :append_to_stamp,
                :stamp_path, :stamped_pdf

    # @see #run
    def default_settings
      {
        text: 'VA.gov',
        x: 5,
        y: 5,
        text_only: false,
        size: 10,
        timestamp: Time.zone.now,
        page_number: nil,
        template: nil,
        multistamp: false
      }.freeze
    end

    # reader for timestamp, ensure there is always a value
    def timestamp
      @timestamp ||= Time.zone.now
    end

    # format timestamp as :pdf_stamp4010007
    def timestamp4010007
      Date.strptime(timestamp.strftime('%m/%d/%Y'), '%m/%d/%Y')
    end

    # generate the stamp/background pdf
    # @see https://www.rubydoc.info/github/sandal/prawn/Prawn/Document
    def generate_stamp
      @stamp_path = Common::FileHelpers.random_file_path
      Prawn::Document.generate(stamp_path, margin: [0, 0]) do |pdf|
        if page_number.present? && template.present?
          raise PdfMissingError, "Template PDF missing: #{template}" unless File.exist?(template)

          reader = PDF::Reader.new(template)
          page_number.times { pdf.start_new_page }
          pdf.draw_text(stamp_text, at: [x, y], size:)
          if timestamp.present?
            # Form 4142 uses this class to create a signature stamp, which doesn't need a timestamp.
            # Ideally, the text_only option should be used to avoid this. However, it isn't the current behavior.
            pdf.draw_text(timestamp.strftime('%Y-%m-%d %I:%M %p %Z'), at: [x, y - 12], size:)
          end
          (reader.page_count - page_number).times { pdf.start_new_page }
        else
          pdf.draw_text(stamp_text, at: [x, y], size:)
        end
      end

      stamp_path
    rescue => e
      log_and_raise_error('Failed to generate stamp', e, STATS_KEY)
    end

    # create the stamp text to be used
    def stamp_text
      stamp = text
      unless text_only
        stamp += if File.basename(file_path) == 'vba_40_10007-stamped.pdf'
                   " #{I18n.l(timestamp4010007, format: :pdf_stamp4010007)}"
                 else
                   " #{I18n.l(timestamp, format: :pdf_stamp_utc)}"
                 end
        stamp += ". #{append_to_stamp}" if append_to_stamp
      end

      stamp
    end

    # combine the input and background pdfs into the stamped_pdf
    # @see https://www.pdflabs.com/docs/pdftk-man-page/#dest-op-stamp
    #
    # pdftk (specifically pdftk-java) has known, longstanding bugs where certain
    # non-conforming AcroForm structures in the input PDF cause it to crash with an
    # unhandled java.lang.ClassCastException (see e.g. gitlab.com/pdftk-java/pdftk
    # issues #17, #45, #47, #110, #139, #166). When that happens we fall back to
    # HexaPDF's watermark CLI, which does not share pdftk-java's AcroForm parsing
    # bugs and is already used elsewhere in this codebase for the same kind of
    # overlay stamping (see PDFUtilities::PDFStamper).
    def stamp_pdf # rubocop:disable Metrics/MethodLength
      Rails.logger.info("Stamping PDF: #{file_path} with stamp: #{stamp_path}")

      raise PdfMissingError, "Original PDF missing: #{file_path}" unless File.exist?(file_path)
      raise PdfMissingError, "Generated stamp missing: #{stamp_path}" unless File.exist?(stamp_path)

      @stamped_pdf = "#{Common::FileHelpers.random_file_path}.pdf"
      begin
        if multistamp
          PDFUtilities::PDFTK.multistamp(file_path, stamp_path, stamped_pdf)
        else
          PDFUtilities::PDFTK.stamp(file_path, stamp_path, stamped_pdf)
        end
      rescue PdfForms::PdftkError => e
        if e.message.include?('ClassCastException')
          Rails.logger.warn(
            "DatestampPdf: pdftk failed with known ClassCastException bug (#{e.class}), " \
            'falling back to HexaPDF watermark stamping'
          )
          StatsD.increment(PDFTK_FALLBACK_STATS_KEY)
          stamp_pdf_with_hexapdf
        else
          raise
        end
      end

      raise StampGenerationError, 'Stamped PDF was not created' unless File.exist?(stamped_pdf)

      stamped_pdf
    rescue => e
      Common::FileHelpers.delete_file_if_exists(stamped_pdf)
      log_and_raise_error('PDF stamping failed', e, STATS_KEY)
    end

    # Fallback stamping path used when pdftk fails with PdfForms::PdftkError.
    # Mirrors PDFUtilities::PDFStamper#stamp_pdf's approach.
    # @see https://github.com/gettalong/hexapdf/blob/master/lib/hexapdf/cli/watermark.rb
    def stamp_pdf_with_hexapdf
      reader = PDF::Reader.new(stamp_path)
      pages = multistamp ? [*1..reader.page_count].join(',') : '1'

      HexaPDF::CLI.run(['watermark', '-w', stamp_path, '-i', pages, '-t', 'stamp', file_path, stamped_pdf])
    end

    # DatestampPdf class
  end
end
