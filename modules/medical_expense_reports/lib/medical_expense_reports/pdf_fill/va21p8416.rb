# frozen_string_literal: true

require 'hexapdf'
require 'pdf_utilities/datestamp_pdf'
require 'pdf_fill/forms/form_base'
require 'pdf_fill/forms/form_helper'
require 'pdf_fill/hash_converter'
require 'medical_expense_reports/constants'
require 'medical_expense_reports/helpers'
require 'medical_expense_reports/pdf_fill/sections/section_01'
require 'medical_expense_reports/pdf_fill/sections/section_02'
require 'medical_expense_reports/pdf_fill/sections/section_03'
require 'medical_expense_reports/pdf_fill/sections/section_04'
require 'medical_expense_reports/pdf_fill/sections/section_05'
require 'medical_expense_reports/pdf_fill/sections/section_06'
require 'medical_expense_reports/pdf_fill/sections/section_07'
require 'medical_expense_reports/pdf_fill/sections/addendum_a'
require 'medical_expense_reports/pdf_fill/sections/addendum_b'
require 'medical_expense_reports/pdf_fill/sections/addendum_c'

module MedicalExpenseReports
  module PdfFill
    # The Va21p8416 Form
    class Va21p8416 < ::PdfFill::Forms::FormBase
      include ::PdfFill::Forms::FormHelper
      include MedicalExpenseReports::Helpers

      # The Form ID
      FORM_ID = MedicalExpenseReports::FORM_ID

      # Hash iterator
      ITERATOR = ::PdfFill::HashConverter::ITERATOR

      # The path to the PDF template for the form
      TEMPLATE = "#{MedicalExpenseReports::MODULE_PATH}/lib/medical_expense_reports/pdf_fill/pdfs/#{FORM_ID}.pdf".freeze

      # Starting page number for overflow pages
      START_PAGE = 11

      # Map question numbers to descriptive titles for overflow attachments
      QUESTION_KEY = [
        { question_number: '1', question_text: "Veteran's Identification Information" },
        { question_number: '2', question_text: "Claimant's Contact Information" },
        { question_number: '3', question_text: 'Reporting Period' },
        { question_number: '4', question_text: 'In-Home Care And Care Facility Expenses' },
        { question_number: '5', question_text: 'Other Medical Expenses' },
        { question_number: '6', question_text: 'Mileage' },
        { question_number: '7', question_text: 'Certification And Signature' },
        { question_number: '8', question_text: 'Witness To Signature' },
        { question_number: '9', question_text: 'In-Home Care Or Care Facility Expenses' },
        { question_number: '10', question_text: 'Other Medical Expenses' },
        { question_number: '11', question_text: 'Mileage For Privately Owned Vehicle Travel For Medical Expenses' },
        { question_number: '12', question_text: 'For A Residential Care, Adult Daycare, Or A Similar Facility' },
        { question_number: '13', question_text: 'For In-Home Attendant Expenses' }
      ].freeze

      # V2-style sections grouping question numbers for overflow pages
      SECTIONS = [
        { label: 'Section I: Veteran\'s Identification Information', question_nums: ['1'] },
        { label: 'Section II: Claimant\'s Contact Information', question_nums: ['2'] },
        { label: 'Section III: Reporting Period', question_nums: ['3'] },
        { label: 'Section IV: In-Home Care And Care Facility Expenses', question_nums: ['4'] },
        { label: 'Section V: Other Medical Expenses', question_nums: ['5'] },
        { label: 'Section VI: Mileage', question_nums: ['6'] },
        { label: 'Section VII: Certification And Signature', question_nums: ['7'] },
        { label: 'Section VIII: Witness To Signature', question_nums: ['8'] },
        { label: 'Addendum A: In-Home Care Or Care Facility Expenses', question_nums: ['9'] },
        { label: 'Addendum B: Other Medical Expenses', question_nums: ['10'] },
        { label: 'Addendum C: Mileage For Privately Owned Vehicle Travel For Medical Expenses', question_nums: ['11'] },
        { label: 'Worksheet 1: Worksheet For A Residential Care, Adult Daycare, Or A Similar Facility',
          question_nums: ['12'] },
        { label: 'Worksheet 2: Worksheet For In-Home Attendant Expenses', question_nums: ['13'] }
      ].freeze

      # The list of section classes for form expansion and key building
      SECTION_CLASSES = [Section1, Section2, Section3,
                         Section4, Section5, Section6,
                         Section7,
                         AddendumA, AddendumB, AddendumC].freeze

      key = {}

      SECTION_CLASSES.each { |section| key.merge!(section::KEY) }

      # Form configuration hash
      KEY = key.freeze

      # Name of the AcroForm field that contains the signature widget
      SIGNATURE_FIELD_NAME = Section7::KEY.dig('statementOfTruthSignature', :key)
      # Font size (points) used when stamping the signature
      SIGNATURE_FONT_SIZE = 10
      # Horizontal padding (points) applied to the derived signature x coordinate
      SIGNATURE_PADDING_X = 2
      # Vertical padding (points) applied to the derived signature y coordinate
      SIGNATURE_PADDING_Y = 1
      # Fallback coordinates if runtime extraction fails
      STATIC_SIGNATURE_COORDINATES = {
        x: 40.8,
        y: 295.3,
        page_number: 4 # zero-indexed; 4 == page 5
      }.freeze

      # Default label column width (points) for redesigned extras in this form
      DEFAULT_LABEL_WIDTH = 130

      # Leading text for the submission date/timestamp/authentication watermark.
      # @see https://design.va.gov/patterns/ask-users-for/signature#date-and-timestamp-watermark-format
      SUBMISSION_STAMP_PREFIX = 'Signed electronically and submitted via VA.gov at '
      # Font size (points) for the two-line submission footer watermark. Kept small and unobtrusive.
      SUBMISSION_STAMP_FONT_SIZE = 7
      # Padding (points) from the right page edge for the right-justified footer. The footer is
      # anchored to the bottom-right so it clears the bottom-left 'VA.GOV' datestamp that
      # SubmitClaimJob#process_document applies to every page.
      SUBMISSION_STAMP_RIGHT_MARGIN = 10
      # Padding (points) from the bottom page edge for the footer's lowest line.
      SUBMISSION_STAMP_BOTTOM_MARGIN = 6
      # StatsD metric emitted when footer stamping fails (fail-open path) so the gap is observable.
      SUBMISSION_STAMP_ERROR_METRIC = 'api.medical_expense_reports.submission_footer_error'

      # Build the authentication-level sentence for the submission watermark based on the
      # submitter's Level of Assurance (LOA). Mirrors the three variants in the VA.gov design system.
      #
      # @param loa [Integer, nil] the submitter's current LOA (nil when unauthenticated)
      # @return [String] the authentication-level sentence
      def self.authentication_stamp_text(loa)
        case loa
        when 3
          'Signee signed with an identity-verified account.'
        when 1, 2
          'Signee signed in but hasn’t verified their identity.'
        else
          'Signee not signed in.'
        end
      end

      # Format a timestamp for the watermark as "HH:MM UTC YYYY-MM-DD" in UTC.
      #
      # @param timestamp [Time, ActiveSupport::TimeWithZone] the time to format
      # @return [String]
      def self.format_submission_timestamp(timestamp)
        "#{timestamp.utc.strftime('%H:%M')} UTC #{timestamp.utc.strftime('%Y-%m-%d')}"
      end

      # Stamp the date/timestamp/authentication-level watermark onto the bottom-right of every page,
      # as two right-justified lines (submission line + authentication line).
      #
      # The timestamp must reflect when the form was initially submitted (not when the PDF was
      # generated), so callers pass the claim's submission time. The footer is drawn with HexaPDF
      # directly onto every page's overlay canvas; this reliably reaches merged-in overflow/attachment
      # pages, which a pdftk stamp does not cover on the first pass.
      #
      # @param pdf_path [String] path to the assembled PDF to stamp
      # @param timestamp [Time, ActiveSupport::TimeWithZone] the submission time (UTC watermark)
      # @param loa [Integer, nil] the submitter's current LOA (nil when unauthenticated)
      # @return [String] path to the stamped PDF, or the original path if stamping fails (fail-open)
      def self.stamp_submission_footer(pdf_path, timestamp, loa)
        return pdf_path if timestamp.blank?

        lines = ["#{SUBMISSION_STAMP_PREFIX}#{format_submission_timestamp(timestamp)}.",
                 authentication_stamp_text(loa)]

        output_path = "#{Common::FileHelpers.random_file_path}.pdf"
        doc = HexaPDF::Document.open(pdf_path)
        font = doc.fonts.add('Helvetica')
        doc.pages.each { |page| draw_footer_on_page(page, font, lines) }
        # validate: false — VA templates use AcroForm field names with periods that newer HexaPDF
        # versions reject during write-time validation (see PdfFill::Filler#merge_pdfs).
        doc.write(output_path, validate: false)
        output_path
      rescue => e
        # Fail open: a footer-stamping failure must not block the veteran's submission. Log and emit a
        # metric so the (rare) gap is observable in Datadog, then return the original PDF so the claim
        # still submits without the watermark.
        Rails.logger.error('MedicalExpenseReports 21P-8416: Error stamping submission footer',
                           error: e.message, backtrace: e.backtrace)
        StatsD.increment(SUBMISSION_STAMP_ERROR_METRIC)
        pdf_path
      end

      # Draw the right-justified footer lines anchored to the bottom-right of a single page.
      #
      # @param page [HexaPDF::Type::Page] the page to stamp
      # @param font [HexaPDF::Font::Type1Wrapper] the Helvetica font (used for width measurement)
      # @param lines [Array<String>] the footer lines, top to bottom
      def self.draw_footer_on_page(page, font, lines)
        size = SUBMISSION_STAMP_FONT_SIZE
        page_width = page.box(:media).width
        canvas = page.canvas(type: :overlay)
        canvas.font('Helvetica', size:)
        lines.each_with_index do |line, index|
          text_width = font.decode_utf8(line).sum(&:width) * size / 1000.0
          x = page_width - SUBMISSION_STAMP_RIGHT_MARGIN - text_width
          y = SUBMISSION_STAMP_BOTTOM_MARGIN + ((lines.size - 1 - index) * (size + 2))
          canvas.text(line, at: [x, y])
        end
      end

      # Stamp a typed signature string onto the PDF using DatestampPdf.
      #
      # @param pdf_path [String] Path to the PDF to stamp
      # @param form_data [Hash] The form data containing the signature
      # @return [String] Path to the stamped PDF (or the original path if signature is blank/on failure)
      def self.stamp_signature(pdf_path, form_data)
        signature_text = form_data['statementOfTruthSignature']
        return pdf_path if signature_text.blank?

        coordinates = signature_overlay_coordinates(pdf_path) || STATIC_SIGNATURE_COORDINATES

        PDFUtilities::DatestampPdf.new(pdf_path).run(
          text: signature_text,
          x: coordinates[:x],
          y: coordinates[:y],
          page_number: coordinates[:page_number],
          size: SIGNATURE_FONT_SIZE,
          text_only: true,
          timestamp: '',
          template: pdf_path,
          multistamp: true
        )
      rescue => e
        Rails.logger.error('MedicalExpenseReports 21P-8416: Error stamping signature',
                           error: e.message, backtrace: e.backtrace)
        pdf_path
      end

      # Post-process form data to match the expected format.
      # Each section of the form is processed in its own expand function.
      #
      # @param _options [Hash] any options needed for post-processing
      #
      # @return [Hash] the processed form data
      #
      def merge_fields(_options = {})
        SECTION_CLASSES.each { |section| section.new.expand(form_data) }

        form_data
      end

      # Derive signature widget coordinates from the PDF template so the stamped
      # signature text can be positioned correctly.
      #
      # @param pdf_path [String] Path to the PDF template
      # @return [Hash, nil] Coordinates hash of the form
      #   `{ x: Float, y: Float, page_number: Integer }` or nil on failure
      def self.signature_overlay_coordinates(pdf_path)
        if Flipper.enabled?(:acroform_debug_logs)
          Rails.logger.info("MedicalExpenseReports::PdfFill::Va21p8416 HexaPDF template: #{pdf_path}")
        end

        doc = HexaPDF::Document.open(pdf_path)
        field = doc.acro_form&.field_by_name(SIGNATURE_FIELD_NAME)
        widget = field&.each_widget&.first
        return unless widget

        rect = widget[:Rect]
        page = doc.object(widget[:P])
        page_index = doc.pages.each_with_index.find { |page_obj, _i| page_obj == page }&.last
        return unless rect && page_index

        llx, lly, _urx, ury = rect
        height = ury - lly
        y = lly + [((height - SIGNATURE_FONT_SIZE) / 2.0), 0].max + SIGNATURE_PADDING_Y

        { x: llx + SIGNATURE_PADDING_X, y:, page_number: page_index }
      rescue => e
        Rails.logger.error('MedicalExpenseReports 21P-8416: Error deriving signature coordinates',
                           error: e.message, backtrace: e.backtrace)
        nil
      end
    end
  end
end
