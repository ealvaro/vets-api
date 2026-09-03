# frozen_string_literal: true

module DocumentClassifier
  module Instrumentation
    PREFIX = 'worker.document_classifier'
    COMPLETED_EVENT = 'document_classification.completed'
    TERMINAL_FAILURE_EVENT = 'document_classification.failed'
    RETRIES_EXHAUSTED_EVENT = 'document_classification.retries_exhausted'
    LOG_SCHEMA_VERSION = 1

    module_function

    def record_success(result)
      Rails.logger.info(COMPLETED_EVENT, success_payload(result))
      StatsD.increment("#{PREFIX}.completed", tags: metric_tags(result))
      StatsD.distribution("#{PREFIX}.latency_ms", result.fetch('latency_ms'), tags: metric_tags(result))
    end

    def success_payload(result)
      pointer, extraction = result.fetch_values('document_pointer', 'extraction')

      {
        schema_version: LOG_SCHEMA_VERSION,
        classification_id: result.fetch('classification_id'),
        document_provider: pointer.fetch('provider'),
        document_uuid: pointer.fetch('document_uuid'),
        current_version_uuid: pointer.fetch('current_version_uuid'),
        predicted_label: result.fetch('predicted_label'),
        confidence: result.fetch('confidence'),
        confidence_score: result.fetch('confidence_score'),
        prompt_version: result.fetch('prompt_version'),
        model: result.fetch('model'),
        latency_ms: result.fetch('latency_ms'),
        extraction_method: extraction.fetch('method'),
        mime_type: extraction.fetch('mime_type'),
        character_count: extraction.fetch('chars'),
        original_character_count: extraction.fetch('original_chars'),
        truncated: extraction.fetch('truncated'),
        ground_truth: nil
      }
    end

    def record_terminal_failure(error:)
      Rails.logger.warn(
        TERMINAL_FAILURE_EVENT,
        schema_version: LOG_SCHEMA_VERSION,
        stage: error_stage(error),
        error_class: error.class.name
      )
    end

    def record_retries_exhausted(error:, job_id:, attempts:)
      Rails.logger.error(
        RETRIES_EXHAUSTED_EVENT,
        schema_version: LOG_SCHEMA_VERSION,
        stage: error_stage(error),
        error_class: error.class.name,
        job_id:,
        attempts:
      )
    end

    def error_stage(error)
      case error
      when ActiveRecord::RecordNotFound then 'upload_lookup'
      when DocumentResolver::Error, Faraday::Error then 'document_resolution'
      when TextExtractor::Error, PDF::Reader::Error then 'text_extraction'
      when Config::Error then 'configuration'
      when VAGptClient::RequestError, Classifier::InvalidResponse then 'classification'
      else 'unknown'
      end
    end

    def metric_tags(result)
      ["prompt_version:#{result.fetch('prompt_version')}", "model:#{result.fetch('model')}"]
    end
  end
end
