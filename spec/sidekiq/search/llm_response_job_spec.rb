# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Search::LlmResponseJob, type: :job do
  let(:memory_store) { ActiveSupport::Cache::MemoryStore.new }
  let(:bedrock_client) { instance_double(Aws::BedrockRuntime::Client) }

  let(:search_id) { 'search-123' }
  let(:query) { 'certificate of eligibility' }
  let(:results) do
    [
      {
        title: 'Certificate of Eligibility',
        url: 'https://www.va.gov/education/',
        excerpt: 'Learn about your Certificate of Eligibility.'
      },
      {
        title: 'GI Bill benefits',
        url: 'https://www.va.gov/education/',
        excerpt: 'Learn about education benefits.'
      }
    ]
  end

  let(:llm_response) { 'You can get a Certificate of Eligibility through VA.gov.' }

  let(:bedrock_content) do
    instance_double(
      Aws::BedrockRuntime::Types::ContentBlock,
      text: llm_response
    )
  end

  let(:bedrock_message) do
    instance_double(
      Aws::BedrockRuntime::Types::Message,
      content: [bedrock_content]
    )
  end

  let(:bedrock_output) do
    instance_double(
      Aws::BedrockRuntime::Types::ConverseOutput,
      message: bedrock_message
    )
  end

  let(:bedrock_response) do
    instance_double(
      Aws::BedrockRuntime::Types::ConverseResponse,
      output: bedrock_output
    )
  end

  around do |example|
    original_store = Rails.cache
    Rails.cache = memory_store
    example.run
  ensure
    Rails.cache = original_store
  end

  before do
    allow(Flipper).to receive(:enabled?).and_call_original

    allow(Flipper)
      .to receive(:enabled?)
      .with(:search_generate_llm_response)
      .and_return(true)

    allow(Aws::BedrockRuntime::Client)
      .to receive(:new)
      .with(region: 'region')
      .and_return(bedrock_client)

    allow(bedrock_client)
      .to receive(:converse)
      .and_return(bedrock_response)

    allow(StatsD).to receive(:increment)
  end

  describe '#perform' do
    context 'when the :search_generate_llm_response flag is enabled' do
      it 'sends the query and results to Bedrock' do
        expect(bedrock_client).to receive(:converse).with(
          model_id: 'prompt_id',
          prompt_variables: {
            query: { text: query },
            results: {
              text: [
                {
                  number: 1,
                  title: 'Certificate of Eligibility',
                  url: 'https://www.va.gov/education/',
                  excerpt: 'Learn about your Certificate of Eligibility.'
                },
                {
                  number: 2,
                  title: 'GI Bill benefits',
                  url: 'https://www.va.gov/education/',
                  excerpt: 'Learn about education benefits.'
                }
              ].to_json
            }
          }
        )

        described_class.new.perform(search_id, query, results)
      end

      it 'caches the generated response' do
        described_class.new.perform(search_id, query, results)

        expect(Rails.cache.read(SearchLlm::Cache.key(search_id))).to eq(llm_response)
      end

      it 'emits a success increment metric' do
        described_class.new.perform(search_id, query, results)

        expect(StatsD).to have_received(:increment)
          .with('api.search.llm_response_job.success')
      end
    end

    context 'when the :search_generate_llm_response flag is disabled' do
      before do
        allow(Flipper)
          .to receive(:enabled?)
          .with(:search_generate_llm_response)
          .and_return(false)
      end

      it 'does not call Bedrock' do
        expect(bedrock_client).not_to receive(:converse)

        described_class.new.perform(search_id, query, results)
      end

      it 'does not cache a response' do
        described_class.new.perform(search_id, query, results)

        expect(Rails.cache.read("search_llm:#{search_id}")).to be_nil
      end

      it 'does not emit a success metric' do
        described_class.new.perform(search_id, query, results)

        expect(StatsD).not_to have_received(:increment)
          .with('api.search.llm_response_job.success')
      end
    end

    context 'when Bedrock raises an error' do
      before do
        allow(bedrock_client)
          .to receive(:converse)
          .and_raise(StandardError, 'Bedrock unavailable')
      end

      it 'increments the error metric and re-raises' do
        expect do
          described_class.new.perform(search_id, query, results)
        end.to raise_error(StandardError, 'Bedrock unavailable')

        expect(StatsD).to have_received(:increment)
          .with('api.search.llm_response_job.error')
      end

      it 'does not emit a success metric' do
        expect do
          described_class.new.perform(search_id, query, results)
        end.to raise_error(StandardError)

        expect(StatsD).not_to have_received(:increment)
          .with('api.search.llm_response_job.success')
      end

      it 'does not cache a response' do
        expect do
          described_class.new.perform(search_id, query, results)
        end.to raise_error(StandardError)

        expect(Rails.cache.read("search_llm:#{search_id}")).to be_nil
      end
    end

    context 'when Bedrock returns no text' do
      let(:bedrock_content) do
        instance_double(
          Aws::BedrockRuntime::Types::ContentBlock,
          text: nil
        )
      end

      it 'does not cache a response' do
        described_class.new.perform(search_id, query, results)

        expect(Rails.cache.read("search_llm:#{search_id}")).to be_nil
      end

      it 'does not emit a success metric' do
        described_class.new.perform(search_id, query, results)

        expect(StatsD).not_to have_received(:increment)
          .with('api.search.llm_response_job.success')
      end
    end
  end
end
