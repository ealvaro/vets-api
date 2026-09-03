# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DocumentClassifier::ClassificationJob, type: :job do
  subject(:perform) { described_class.new.perform(upload.id) }

  let(:upload) { create(:lighthouse526_document_upload, document_type: 'Veteran Upload') }
  let(:resolver) { instance_double(DocumentClassifier::DocumentResolver) }
  let(:pointer) do
    {
      'provider' => 'benefits_documents',
      'document_uuid' => 'document-uuid',
      'current_version_uuid' => 'version-uuid',
      'original_filename' => 'evidence.pdf'
    }
  end
  let(:extraction) do
    {
      'text' => 'extracted document content',
      'method' => 'embedded',
      'mime_type' => 'application/pdf',
      'chars' => 26,
      'original_chars' => 26,
      'truncated' => false
    }
  end
  let(:classification) do
    {
      'predicted_label' => 'L014',
      'confidence' => 'high',
      'confidence_score' => 0.95,
      'reasoning' => 'Form title match',
      'prompt_version' => 'document-classifier-v1',
      'model' => 'test-model',
      'latency_ms' => 123.45
    }
  end

  before do
    allow(Flipper).to receive(:enabled?).with(:enable_document_classification).and_return(true)
    allow(DocumentClassifier::DocumentResolver).to receive(:new).with(upload:).and_return(resolver)
    allow(resolver).to receive(:resolve).and_return(pointer)
    allow(resolver).to receive(:download).with(pointer).and_return('document bytes')
    allow(DocumentClassifier::TextExtractor).to receive(:call)
      .with('document bytes', filename: 'evidence.pdf').and_return(extraction)
    allow(DocumentClassifier::Classifier).to receive(:classify)
      .with(document_content: 'extracted document content').and_return(classification)
    allow(DocumentClassifier::Classifier).to receive(:classification_id).and_return('classification-id')
    allow(DocumentClassifier::Instrumentation).to receive(:record_success)
  end

  it 'resolves, downloads, extracts, and classifies the completed upload' do
    expect(perform).to include(
      'classification_id' => 'classification-id',
      'predicted_label' => 'L014',
      'document_pointer' => pointer.except('original_filename'),
      'extraction' => extraction.except('text')
    )
  end

  it 'does not include extracted document text in its result' do
    expect(perform.dig('extraction', 'text')).to be_nil
  end

  it 'does not include the potentially sensitive original filename in its result' do
    expect(perform.dig('document_pointer', 'original_filename')).to be_nil
  end

  it 'records the successful classification' do
    result = perform

    expect(DocumentClassifier::Instrumentation).to have_received(:record_success).with(result)
  end

  context 'when the feature is disabled before execution' do
    before do
      allow(Flipper).to receive(:enabled?).with(:enable_document_classification).and_return(false)
    end

    it 'does not resolve the document' do
      perform

      expect(DocumentClassifier::DocumentResolver).not_to have_received(:new)
      expect(DocumentClassifier::Instrumentation).not_to have_received(:record_success)
    end
  end

  describe 'retry behavior' do
    it 'uses a bounded retry window and suppresses duplicate upload jobs' do
      expect(described_class.get_sidekiq_options).to include('retry' => 7, 'unique_for' => 1.hour)
    end

    it 'retries while the Documents pointer is not yet available' do
      error = DocumentClassifier::DocumentResolver::NotReady.new('not ready')

      expect(described_class.sidekiq_retry_in_block.call(0, error)).to be_nil
    end

    it 'does not retry ambiguous document matches' do
      error = DocumentClassifier::DocumentResolver::AmbiguousMatch.new('ambiguous')

      expect(described_class.sidekiq_retry_in_block.call(0, error)).to eq(:kill)
    end

    it 'records a terminal failure without logging its message' do
      error = DocumentClassifier::DocumentResolver::AmbiguousMatch.new('potentially sensitive content')
      allow(resolver).to receive(:resolve).and_raise(error)
      allow(DocumentClassifier::Instrumentation).to receive(:record_terminal_failure)

      expect { perform }.to raise_error(error)
      expect(DocumentClassifier::Instrumentation).to have_received(:record_terminal_failure).with(error:)
    end

    it 'does not record a terminal failure while an error remains retryable' do
      error = DocumentClassifier::DocumentResolver::NotReady.new('not ready')
      allow(resolver).to receive(:resolve).and_raise(error)
      allow(DocumentClassifier::Instrumentation).to receive(:record_terminal_failure)

      expect { perform }.to raise_error(error)
      expect(DocumentClassifier::Instrumentation).not_to have_received(:record_terminal_failure)
    end

    it 'retries transient VA GPT responses' do
      error = DocumentClassifier::VAGptClient::RequestError.new('unavailable', status: 503)

      expect(described_class.sidekiq_retry_in_block.call(0, error)).to be_nil
    end

    it 'does not retry permanent VA GPT responses' do
      error = DocumentClassifier::VAGptClient::RequestError.new('invalid request', status: 400)

      expect(described_class.sidekiq_retry_in_block.call(0, error)).to eq(:kill)
    end

    it 'records retry exhaustion without raw exception content' do
      error = DocumentClassifier::DocumentResolver::NotReady.new('potentially sensitive content')
      allow(DocumentClassifier::Instrumentation).to receive(:record_retries_exhausted)

      described_class.sidekiq_retries_exhausted_block.call(
        { 'jid' => 'job-id', 'retry_count' => 7 },
        error
      )

      expect(DocumentClassifier::Instrumentation).to have_received(:record_retries_exhausted).with(
        error:,
        job_id: 'job-id',
        attempts: 8
      )
    end
  end
end
