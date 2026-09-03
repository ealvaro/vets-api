# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DocumentClassifier::Instrumentation do
  describe '.record_success' do
    let(:result) do
      {
        'classification_id' => 'classification-id',
        'document_pointer' => {
          'provider' => 'benefits_documents',
          'document_uuid' => 'document-uuid',
          'current_version_uuid' => 'version-uuid'
        },
        'predicted_label' => 'L014',
        'confidence' => 'high',
        'confidence_score' => 0.95,
        'reasoning' => 'Potentially sensitive model reasoning',
        'prompt_version' => 'document-classifier-v1',
        'model' => 'test-model',
        'latency_ms' => 123.45,
        'extraction' => {
          'method' => 'embedded',
          'mime_type' => 'application/pdf',
          'chars' => 1000,
          'original_chars' => 1200,
          'truncated' => true
        }
      }
    end
    let(:tags) { ['prompt_version:document-classifier-v1', 'model:test-model'] }

    before do
      allow(Rails.logger).to receive(:info)
      allow(StatsD).to receive(:increment)
      allow(StatsD).to receive(:distribution)
    end

    it 'writes one PII-safe structured evaluation record' do
      described_class.record_success(result)

      expect(Rails.logger).to have_received(:info).with(
        'document_classification.completed',
        hash_including(
          schema_version: 1,
          classification_id: 'classification-id',
          document_uuid: 'document-uuid',
          current_version_uuid: 'version-uuid',
          predicted_label: 'L014',
          ground_truth: nil
        )
      )
      payload = described_class.success_payload(result)
      expect(payload).not_to have_key(:reasoning)
      expect(payload).not_to have_key(:text)
      expect(payload).not_to have_key(:original_filename)
    end

    it 'emits only completion and latency metrics' do
      described_class.record_success(result)

      expect(StatsD).to have_received(:increment).with('worker.document_classifier.completed', tags:)
      expect(StatsD).to have_received(:distribution)
        .with('worker.document_classifier.latency_ms', 123.45, tags:)
    end
  end

  describe 'failure logging' do
    before do
      allow(Rails.logger).to receive(:warn)
      allow(Rails.logger).to receive(:error)
    end

    it 'records terminal failures without the exception message' do
      error = DocumentClassifier::DocumentResolver::AmbiguousMatch.new('potentially sensitive content')

      described_class.record_terminal_failure(error:)

      expect(Rails.logger).to have_received(:warn).with(
        'document_classification.failed',
        schema_version: 1,
        stage: 'document_resolution',
        error_class: 'DocumentClassifier::DocumentResolver::AmbiguousMatch'
      )
    end

    it 'records retry exhaustion without the exception message' do
      error = DocumentClassifier::VAGptClient::RequestError.new('potentially sensitive content', status: 503)

      described_class.record_retries_exhausted(error:, job_id: 'job-id', attempts: 8)

      expect(Rails.logger).to have_received(:error).with(
        'document_classification.retries_exhausted',
        schema_version: 1,
        stage: 'classification',
        error_class: 'DocumentClassifier::VAGptClient::RequestError',
        job_id: 'job-id',
        attempts: 8
      )
    end
  end
end
