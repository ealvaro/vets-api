# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DocumentClassifier::Config do
  describe '.validate!' do
    it 'accepts a complete VA GPT configuration' do
      allow(described_class).to receive_messages(
        api_key: 'secret',
        api_version: 'test-version',
        base_url: 'https://example.va.gov/foundry/openai/',
        model: 'test-deployment'
      )

      expect { described_class.validate! }.not_to raise_error
    end

    it 'identifies missing required settings without exposing configured values' do
      allow(described_class).to receive_messages(
        api_key: '',
        api_version: 'test-version',
        base_url: 'https://example.va.gov/',
        model: ''
      )

      expect { described_class.validate! }
        .to raise_error(described_class::Error, 'Missing document classifier VA GPT settings: api_key, model')
    end

    it 'does not turn a missing base URL into a valid root path' do
      allow(described_class).to receive(:settings).and_return(double(base_url: nil))

      expect(described_class.base_url).to eq('')
    end

    it 'normalizes the base URL and response path for relative requests' do
      allow(described_class).to receive(:settings).and_return(
        double(base_url: 'https://example.va.gov/foundry/openai/', responses_path: '/responses')
      )

      expect(described_class.base_url).to eq('https://example.va.gov/foundry/openai/')
      expect(described_class.responses_path).to eq('responses')
    end
  end
end
