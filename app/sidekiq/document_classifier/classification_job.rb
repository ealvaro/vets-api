# frozen_string_literal: true

module DocumentClassifier
  # Classifies a completed 526 Veteran upload without changing its upload lifecycle.
  class ClassificationJob
    include Sidekiq::Job

    POINTER_RESULT_FIELDS = %w[provider document_uuid current_version_uuid].freeze
    RETRYABLE_HTTP_STATUSES = [408, 409, 429].freeze
    NON_RETRYABLE_ERRORS = [
      ActiveRecord::RecordNotFound,
      Config::Error,
      DocumentResolver::InvalidUpload,
      DocumentResolver::AmbiguousMatch,
      TextExtractor::UnsupportedDocument,
      TextExtractor::DocumentTooLarge,
      TextExtractor::PageLimitExceeded,
      TextExtractor::EmptyDocument,
      TextExtractor::OcrFailed,
      PDF::Reader::Error
    ].freeze

    sidekiq_options retry: 7, unique_for: 1.hour

    sidekiq_retry_in do |_count, exception|
      :kill unless ClassificationJob.retryable_error?(exception)
    end

    sidekiq_retries_exhausted do |message, exception|
      Instrumentation.record_retries_exhausted(
        error: exception,
        job_id: message['jid'],
        attempts: message['retry_count'].to_i + 1
      )
    end

    def self.retryable_error?(error)
      return false if NON_RETRYABLE_ERRORS.any? { |error_class| error.is_a?(error_class) }
      return retryable_http_status?(error.status) if error.is_a?(VAGptClient::RequestError) && error.status

      true
    end

    def self.retryable_http_status?(status)
      status.to_i >= 500 || RETRYABLE_HTTP_STATUSES.include?(status.to_i)
    end

    def perform(lighthouse526_document_upload_id)
      return unless Flipper.enabled?(:enable_document_classification)

      upload = Lighthouse526DocumentUpload.find(lighthouse526_document_upload_id)
      resolver = DocumentResolver.new(upload:)
      pointer = resolver.resolve
      content = resolver.download(pointer)
      extraction = TextExtractor.call(content, filename: pointer.fetch('original_filename'))
      classification = Classifier.classify(document_content: extraction.fetch('text'))

      result = build_result(pointer, extraction, classification)
      Instrumentation.record_success(result)
      result
    rescue => e
      Instrumentation.record_terminal_failure(error: e) unless self.class.retryable_error?(e)
      raise
    end

    private

    def build_result(pointer, extraction, classification)
      classification.merge(
        'classification_id' => Classifier.classification_id(
          document_uuid: pointer.fetch('document_uuid'),
          current_version_uuid: pointer.fetch('current_version_uuid'),
          model: classification.fetch('model'),
          prompt_version: classification.fetch('prompt_version')
        ),
        'document_pointer' => pointer.slice(*POINTER_RESULT_FIELDS),
        'extraction' => extraction.except('text')
      )
    end
  end
end
