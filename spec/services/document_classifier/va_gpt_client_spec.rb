# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DocumentClassifier::VAGptClient do
  describe DocumentClassifier::VAGptClient::Client do
    let(:stubs) { Faraday::Adapter::Test::Stubs.new }
    let(:connection) do
      Faraday.new(url: 'https://example.va.gov/foundry/openai/') do |faraday|
        faraday.request :json
        faraday.response :json
        faraday.adapter :test, stubs
      end
    end
    let(:client) do
      described_class.new(connection:, api_version: 'test-version', responses_path: 'responses')
    end

    after { stubs.verify_stubbed_calls }

    it 'sends a Responses API request through the configured connection' do
      stubs.post('/foundry/openai/responses') do |environment|
        expect(environment.params).to include('api-version' => 'test-version')
        expect(JSON.parse(environment.body)).to include('model' => 'test-deployment')

        [200, { 'Content-Type' => 'application/json' }, { output_text: 'classified' }.to_json]
      end

      response = client.responses.create(parameters: { model: 'test-deployment', input: [] })

      expect(response).to eq('output_text' => 'classified')
    end

    it 'raises a safe typed error for an unsuccessful response' do
      error = Faraday::ServerError.new('failed', { status: 503 })
      allow(connection).to receive(:post).and_raise(error)

      expect { client.responses.create(parameters: {}) }
        .to raise_error(DocumentClassifier::VAGptClient::RequestError, 'VA GPT request failed status=503')
    end
  end

  describe '.build_connection' do
    it 'configures authentication and timeouts without another client dependency' do
      allow(DocumentClassifier::Config).to receive_messages(
        api_key: 'secret',
        base_url: 'https://example.va.gov/foundry/openai/',
        open_timeout: 10,
        read_timeout: 60
      )

      connection = described_class.build_connection

      expect(connection.headers['api-key']).to eq('secret')
      expect(connection.options.open_timeout).to eq(10)
      expect(connection.options.timeout).to eq(60)
    end
  end
end
