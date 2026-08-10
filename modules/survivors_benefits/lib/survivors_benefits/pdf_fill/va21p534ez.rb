# frozen_string_literal: true

require 'hexapdf'
require 'pdf_fill/forms/form_base'
require 'pdf_fill/forms/form_helper'
require 'pdf_fill/hash_converter'
require 'pdf_utilities/datestamp_pdf'
require 'survivors_benefits/constants'
require 'survivors_benefits/helpers'

Dir[File.expand_path('sections/V2022/section_*.rb', __dir__)].each do |file|
  require file
end

Dir[File.expand_path('sections/V2025/section_*.rb', __dir__)].each do |file|
  require file
end

module SurvivorsBenefits
  module PdfFill
    # The Va21p8416 Form
    class Va21p534ez < ::PdfFill::Forms::FormBase
      include ::PdfFill::Forms::FormHelper
      include SurvivorsBenefits::Helpers

      # The Form ID
      FORM_ID = SurvivorsBenefits::FORM_ID

      # Hash iterator
      ITERATOR = ::PdfFill::HashConverter::ITERATOR

      # Starting page number for overflow pages
      START_PAGE = 11

      # Map question numbers to descriptive titles for overflow attachments
      QUESTION_KEY = [
        { question_number: '1', question_text: 'Veteran\'s Identification Information' },
        { question_number: '2', question_text: 'Claimant\'s Contact Information' },
        { question_number: '3', question_text: 'Veteran\'s Service Information' },
        { question_number: '4', question_text: 'Marital Information' },
        { question_number: '5', question_text: 'Marital History' },
        { question_number: '6', question_text: 'Child of the Veteran Information' },
        { question_number: '7', question_text: 'Dependency and Indemnity Compensation (DIC)' },
        { question_number: '8', question_text: 'Nursing Home or Increased Survivors Entitlement' },
        { question_number: '9', question_text: 'Income and Assets' },
        { question_number: '10', question_text: 'Information About Your Medical or Other Expenses' },
        { question_number: '11', question_text: 'Direct Deposit Information (Must Complete)' },
        { question_number: '12', question_text: 'Claim Certification and Signature (Must Complete)' },
        { question_number: '13', question_text: 'Witness to Signature' }
      ].freeze

      # V2-style sections grouping question numbers for overflow pages
      SECTIONS = [
        { label: 'Section I: Veteran\'s Identification Information', question_nums: ['1'] },
        { label: 'Section II: Claimant\'s Contact Information', question_nums: ['2'] },
        { label: 'Section III: Veteran\'s Service Information', question_nums: ['3'] },
        { label: 'Section IV: Marital Information', question_nums: ['4'] },
        { label: 'Section V: Marital History', question_nums: ['5'] },
        { label: 'Section VI: Child of the Veteran Information', question_nums: ['6'] },
        { label: 'Section VII: Dependency and Indemnity Compensation (DIC)', question_nums: ['7'] },
        { label: 'Section VIII: Nursing Home or Increased Survivors Entitlement', question_nums: ['8'] },
        { label: 'Section IX: Income and Assets', question_nums: ['9'] },
        { label: 'Section X: Information About Your Medical or Other Expenses', question_nums: ['10'] },
        { label: 'Section XI: Direct Deposit Information (Must Complete)', question_nums: ['11'] },
        { label: 'Section XII: Claim Certification and Signature (Must Complete)', question_nums: ['12'] },
        { label: 'Section XIII: Witness to Signature', question_nums: ['13'] }
      ].freeze

      # Font size (points) used when stamping the signature
      SIGNATURE_FONT_SIZE = 10
      # Horizontal padding (points) applied to the derived signature x coordinate
      SIGNATURE_PADDING_X = 2
      # Vertical padding (points) applied to the derived signature y coordinate
      SIGNATURE_PADDING_Y = 1
      # Zero-based page index where the signature widget lives (visible page 18)
      SIGNATURE_PAGE_INDEX = 17

      # Default label column width (points) for redesigned extras in this form
      DEFAULT_LABEL_WIDTH = 130

      # Leading text for the submission date/timestamp/authentication watermark.
      # @see https://design.va.gov/patterns/ask-users-for/signature#date-and-timestamp-watermark-format
      SUBMISSION_STAMP_PREFIX = 'Signed electronically and submitted via VA.gov at '
      # Authentication-level sentence for the watermark. The 21P-534EZ is only reachable by a fully
      # identity-verified (IAL2) submitter, so the IAL1/unauthenticated variants cannot occur and the
      # level is fixed — the same assumption the shared ExtrasGeneratorV2 footer already makes.
      SUBMISSION_STAMP_AUTH_TEXT = 'Signee signed with an identity-verified account.'
      # Font size (points) for the two-line submission footer watermark. Kept small and unobtrusive.
      SUBMISSION_STAMP_FONT_SIZE = 7
      # Padding (points) from the right page edge for the right-justified footer. The footer is
      # anchored to the bottom-right so it clears the bottom-left 'VA.GOV' datestamp that
      # SubmitClaimJob#process_document applies to every page.
      SUBMISSION_STAMP_RIGHT_MARGIN = 10
      # Padding (points) from the bottom page edge for the footer's lowest line.
      SUBMISSION_STAMP_BOTTOM_MARGIN = 6
      # StatsD metric emitted when footer stamping fails (fail-open path) so the gap is observable.
      SUBMISSION_STAMP_ERROR_METRIC = 'api.survivors_benefits.submission_footer_error'

      SECTION_CLASS_NAMES = (1..12).map { |n| "Section#{n}" }.freeze

      class << self
        def pdf_version
          Flipper.enabled?(:survivors_benefits_form_2025_version_enabled) ? :v2025 : :v2022
        end

        def template_path
          version = pdf_version == :v2025 ? 'V2025' : 'V2022'
          "#{SurvivorsBenefits::MODULE_PATH}/lib/survivors_benefits/pdf_fill/pdfs/#{version}/#{FORM_ID}.pdf"
        end

        def signature_field_name(form_data = nil)
          field_index = signature_field_index(form_data)
          subform_index = pdf_version == :v2025 ? 163 : 218
          "form1[0].#subform[#{subform_index}].SignatureField1[#{field_index}]"
        end

        def signature_field_index(form_data = nil)
          relationship = form_data&.[]('claimantRelationship')
          SurvivorsBenefits::Helpers.signature_field_index_for_claimant_relationship(relationship)
        end

        def section_classes
          if pdf_version == :v2025
            SECTION_CLASS_NAMES.map { |class_name| SurvivorsBenefits::PdfFill::V2025.const_get(class_name) }.freeze
          else
            SECTION_CLASS_NAMES.map { |class_name| SurvivorsBenefits::PdfFill.const_get(class_name) }.freeze
          end
        end

        def key
          section_classes.each_with_object({}) do |section, merged_key|
            merged_key.merge!(section::KEY)
          end.freeze
        end

        # Backward compatibility for callers that still reference class constants.
        def const_missing(name)
          return template_path if name == :TEMPLATE
          return signature_field_name if name == :SIGNATURE_FIELD_NAME
          return key if name == :KEY

          super
        end
      end

      # Filler checks instance methods first for dynamic form configuration.
      def template
        self.class.template_path
      end

      # Keep key resolution aligned with dynamic form behavior.
      delegate :key, to: :class

      # Post-process form data to match the expected format.
      # Each section of the form is processed in its own expand function.
      #
      # @param _options [Hash] any options needed for post-processing
      #
      # @return [Hash] the processed form data
      #
      def merge_fields(_options = {})
        self.class.section_classes.each { |section| section.new.expand(form_data) }
        form_data
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
      # @return [String] path to the stamped PDF, or the original path if stamping fails (fail-open)
      def self.stamp_submission_footer(pdf_path, timestamp)
        return pdf_path if pdf_path.blank? || timestamp.blank?

        lines = ["#{SUBMISSION_STAMP_PREFIX}#{format_submission_timestamp(timestamp)}.",
                 SUBMISSION_STAMP_AUTH_TEXT]

        output_path = "#{Common::FileHelpers.random_file_path}.pdf"
        doc = HexaPDF::Document.open(pdf_path)
        font = doc.fonts.add('Helvetica')
        doc.pages.each { |page| draw_footer_on_page(page, font, lines) }
        # validate: false — VA templates use AcroForm field names with periods that newer HexaPDF
        # versions reject during write-time validation (see PdfFill::Filler#merge_pdfs).
        doc.write(output_path, validate: false)
        output_path
      rescue => e
        # Fail open: a footer-stamping failure must not block the claimant's submission. Log and emit a
        # metric so the (rare) gap is observable in Datadog, then return the original PDF so the claim
        # still submits without the watermark.
        Rails.logger.error('SurvivorsBenefits 21P-534EZ: Error stamping submission footer',
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
        return pdf_path if pdf_path.blank?

        signature_text = signature_text_for(form_data)
        return pdf_path if signature_text.blank?

        coordinates = signature_overlay_coordinates(pdf_path, form_data:) ||
                      signature_overlay_coordinates(template_path, form_data:)
        unless coordinates
          Rails.logger.warn(
            'SurvivorsBenefits 21P-534EZ: Unable to derive signature coordinates; returning original PDF',
            pdf_path:
          )
          return pdf_path
        end

        stamp_pdf(pdf_path, signature_text, coordinates)
      rescue => e
        Rails.logger.error('SurvivorsBenefits 21P-534EZ: Error stamping signature',
                           error: e.message, backtrace: e.backtrace)
        pdf_path
      end

      # Derive signature widget coordinates from the PDF template so the stamped
      # signature text can be positioned correctly.
      #
      # @param pdf_path [String] Path to the PDF template
      # @return [Hash, nil] Coordinates hash of the form
      #   `{ x: Float, y: Float, page_number: Integer }` or nil on failure
      def self.signature_overlay_coordinates(pdf_path = nil, form_data: nil)
        pdf_path ||= template_path
        signature_overlay_coordinates_for(pdf_path, form_data:)
      rescue => e
        Rails.logger.error('SurvivorsBenefits 21P-534EZ: Error deriving signature coordinates',
                           error: e.message, backtrace: e.backtrace)
        nil
      end

      def self.signature_overlay_coordinates_for(pdf_path, form_data: nil)
        if Flipper.enabled?(:acroform_debug_logs)
          Rails.logger.info("SurvivorsBenefits::PdfFill::Va21p534ez HexaPDF template: #{pdf_path}")
        end

        HexaPDF::Document.open(pdf_path) do |doc|
          field = doc.acro_form&.field_by_name(signature_field_name(form_data))
          widget = field&.each_widget&.first
          next unless widget

          rect = widget[:Rect]
          next unless rect

          llx, lly, _urx, ury = rect
          height = ury - lly
          y = lly + [((height - SIGNATURE_FONT_SIZE) / 2.0), 0].max + SIGNATURE_PADDING_Y

          { x: llx + SIGNATURE_PADDING_X, y:, page_number: SIGNATURE_PAGE_INDEX }
        end
      end

      def self.signature_text_for(form_data)
        form_data['claimantSignature'].presence ||
          form_data['statementOfTruthSignature'].presence ||
          signers_full_name(form_data)
      end

      # For a custodian filing, the frontend renames `yourName` to `filingCustodianFullName` but
      # leaves the original key in the payload; prefer the canonical key so this keeps working if
      # `your*` is ever pruned, which would otherwise stamp the *child's* name on §14A.
      def self.signers_full_name(form_data)
        # Deliberately no claimantFullName fallback: for a custodian filing that key holds the
        # *child's* name, which must never land on the alternate-signer line.
        name = form_data&.[]('filingCustodianFullName').presence || form_data&.[]('yourName')

        [name&.[]('first'), name&.[]('middle'), name&.[]('last')].compact_blank.join(' ')
      end

      def self.stamp_pdf(pdf_path, signature_text, coordinates)
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
      end
    end
  end
end
