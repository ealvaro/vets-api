# frozen_string_literal: true

require 'rails_helper'
require 'search_kendra/configuration'

describe SearchKendra::Configuration do
  subject(:config) { described_class.instance }

  let(:client) { instance_double(Aws::Kendra::Client) }

  before do
    config.remove_instance_variable(:@client) if config.instance_variable_defined?(:@client)

    allow(Settings.search_kendra).to receive_messages(
      index_id: 'test-index',
      region: 'us-gov-west-1'
    )

    allow(Aws::Kendra::Client).to receive(:new)
      .with(region: 'us-gov-west-1')
      .and_return(client)
  end

  describe '#service_name' do
    it 'returns the service name' do
      expect(config.service_name).to eq('SearchKendra/Results')
    end
  end

  describe '#index_id' do
    it 'returns the configured index id' do
      expect(config.index_id).to eq('test-index')
    end
  end

  describe '#region' do
    it 'returns the configured region' do
      expect(config.region).to eq('us-gov-west-1')
    end
  end

  describe '#client' do
    it 'returns an Aws::Kendra::Client' do
      expect(config.client).to be(client)
    end

    it 'memoizes the client' do
      2.times { config.client }

      expect(Aws::Kendra::Client).to have_received(:new).once
    end

    it 'constructs the client with the configured region' do
      config.client

      expect(Aws::Kendra::Client)
        .to have_received(:new)
        .with(region: 'us-gov-west-1')
    end
  end
end
