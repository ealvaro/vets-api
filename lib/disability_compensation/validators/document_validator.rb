# frozen_string_literal: true

require 'common/file_helpers'

module DisabilityCompensation
  module Validators
    class DocumentValidator
      # Warning constants returned in the warnings array
      WRONG_FORM = 'wrong_form'
      UNABLE_TO_VALIDATE = 'unable_to_validate'

      # Maximum time (in seconds) allowed for OCR processing
      OCR_TIMEOUT = 60

      # StatsD metric prefix for tracking validation outcomes
      STATSD_KEY_PREFIX = 'api.form526.document_validation'

      # Values can be:
      #   - An Array of strings: uses default phrase-matching validation
      #   - A class responding to #validate(extracted_text): uses custom validation logic
      SUPPORTED_ATTACHMENT_IDS = {
        'L1839' => ['Separation Health Assessment', 'Part A']
      }.freeze

      attr_reader :file_path, :attachment_id, :in_progress_form_id

      def initialize(file_path, attachment_id:, in_progress_form_id: nil)
        @file_path = file_path
        @attachment_id = attachment_id
        @in_progress_form_id = in_progress_form_id
      end

      def validate
        validator_config = SUPPORTED_ATTACHMENT_IDS[@attachment_id]
        unless validator_config
          track_metric('unsupported_attachment_id')
          return []
        end

        warnings = []
        extracted_text = Timeout.timeout(OCR_TIMEOUT) { perform_ocr }
        warnings << WRONG_FORM unless document_matches?(validator_config, extracted_text)
        log_warnings(warnings) if warnings.any?

        outcome = warnings.empty? ? 'match' : 'mismatch'
        track_metric(outcome)
        warnings
      rescue Timeout::Error
        log_timeout
        [UNABLE_TO_VALIDATE]
      rescue => e
        log_error(e)
        [UNABLE_TO_VALIDATE]
      end

      private

      def log_timeout
        Rails.logger.error(
          'DocumentValidator OCR validation timed out',
          { attachment_id: @attachment_id, in_progress_form_id: @in_progress_form_id,
            timeout_seconds: OCR_TIMEOUT }
        )
        track_metric('timeout')
      end

      def log_error(error)
        Rails.logger.error(
          'DocumentValidator OCR validation failed',
          { attachment_id: @attachment_id, in_progress_form_id: @in_progress_form_id,
            error_class: error.class.name, error_message: error.message.to_s.truncate(200) }
        )
        track_metric('error')
        [UNABLE_TO_VALIDATE]
      end

      def track_metric(outcome)
        # Normalize attachment_id to prevent high-cardinality metrics from untrusted user input
        # Only supported IDs are tagged; all others normalize to 'unsupported'
        normalized_attachment_id = SUPPORTED_ATTACHMENT_IDS.key?(@attachment_id) ? @attachment_id : 'unsupported'

        StatsD.increment(
          "#{STATSD_KEY_PREFIX}.run",
          tags: ["outcome:#{outcome}", "attachment_id:#{normalized_attachment_id}"]
        )
      end

      def log_warnings(warnings)
        Rails.logger.warn(
          'DocumentValidator validation warnings',
          { attachment_id: @attachment_id, in_progress_form_id: @in_progress_form_id, warnings: }
        )
      end

      def perform_ocr
        image_path = Rails.root.join("#{Common::FileHelpers.random_file_path}.jpg").to_s
        prepare_image_for_ocr(image_path)
        RTesseract.new(image_path).to_s
      ensure
        FileUtils.rm_f(image_path) if image_path && File.exist?(image_path)
      end

      def document_matches?(validator_config, extracted_text)
        if validator_config.is_a?(Array)
          validator_config.all? { |phrase| extracted_text.include?(phrase) }
        else
          validator_config.new.validate(extracted_text)
        end
      end

      def prepare_image_for_ocr(image_path)
        if pdf_file?
          convert_pdf_to_image(image_path)
        else
          FileUtils.cp(@file_path, image_path)
        end
      end

      def convert_pdf_to_image(output_path)
        pdf = MiniMagick::Image.open(@file_path)
        convert = MiniMagick::Tool.new('convert')
        convert.background 'white'
        convert.flatten
        convert.density 150
        convert.quality 100
        convert << pdf.pages.first.path
        convert << output_path
        convert.call
      ensure
        pdf&.destroy!
      end

      def pdf_file?
        File.extname(@file_path).downcase == '.pdf'
      end
    end
  end
end
