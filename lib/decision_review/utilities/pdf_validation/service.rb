# frozen_string_literal: true

require 'decision_review/utilities/pdf_validation/configuration'

module DecisionReview
  ##
  # Proxy Service for the Lighthouse PDF validation endpoint.
  #
  module PdfValidation
    class Service < Common::Client::Base
      include Common::Client::Concerns::Monitoring

      configuration DecisionReview::PdfValidation::Configuration

      STATSD_KEY_PREFIX = 'api.decision_review.pdf_validation'
      LH_ERROR_KEY = 'errors'
      LH_ERROR_DETAIL_KEY = 'detail'
      GENERIC_FAILURE_MESSAGE = 'Something went wrong...'

      def validate_pdf_with_lighthouse(file)
        with_monitoring do
          perform(:post, 'uploads/validate_document',
                  file.read,
                  { 'Content-Type' => 'application/pdf', 'Transfer-Encoding' => 'chunked' })
        end
      rescue Common::Client::Errors::ClientError => e
        handle_client_error(e)
      rescue => e
        handle_unexpected_error(e)
      end

      private

      def handle_client_error(error)
        validation_failure_detail = extract_error_detail(error)
        monitor.track_request(
          :error,
          'Decision Review Upload failed PDF validation.',
          "#{STATSD_KEY_PREFIX}.validate_pdf_with_lighthouse.pdf_validation_failure",
          call_location: caller_locations.first,
          error: error.message,
          validation_failure_detail:
        )
        raise Common::Exceptions::UnprocessableEntity.new(
          detail: validation_failure_detail,
          source: 'FormAttachment.lighthouse_validation.invalid_pdf'
        )
      end

      def handle_unexpected_error(error)
        monitor.track_request(
          :error,
          'Decision Review Upload failed with an unexpected failure case. Investigation Required.',
          "#{STATSD_KEY_PREFIX}.validate_pdf_with_lighthouse.unexpected_failure",
          call_location: caller_locations.first,
          error: error.message
        )
        raise Common::Exceptions::UnprocessableEntity.new(
          detail: GENERIC_FAILURE_MESSAGE,
          source: 'FormAttachment.lighthouse_validation.unknown_error'
        )
      end

      def extract_error_detail(error)
        detail = error.body&.dig(LH_ERROR_KEY)&.map { |d| d[LH_ERROR_DETAIL_KEY] }&.join("\n")
        detail.presence || GENERIC_FAILURE_MESSAGE
      end

      def monitor
        @monitor ||= Logging::Monitor.new('decision_review_pdf_validation',
                                          allowlist: %w[validation_failure_detail error])
      end
    end
  end
end
