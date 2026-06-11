# frozen_string_literal: true

require 'rails_helper'
require 'vha_notification/configuration'

RSpec.describe VHANotification::Configuration do
  subject(:config) { described_class.instance }

  describe '#base_path' do
    it 'returns the configured base URL' do
      expect(config.base_path).to eq(Settings.vha_notification.base_url)
    end
  end

  describe '#service_name' do
    it 'returns VHANotification' do
      expect(config.service_name).to eq('VHANotification')
    end
  end

  describe '#connection' do
    after { config.instance_variable_set(:@conn, nil) }

    it 'returns a Faraday connection' do
      expect(config.connection).to be_a(Faraday::Connection)
    end
  end

  describe '#post_consent_update' do
    let(:connection) { instance_double(Faraday::Connection) }
    let(:response) { instance_double(Faraday::Response) }
    let(:pid) { '123456789' }
    let(:payload) { { source: 'ibm', vhaCommsConsent: true, participantId: 123_456_789 } }
    let(:bearer_token) { 'bearer-123' }

    before do
      config.instance_variable_set(:@conn, connection)
      allow(connection).to receive(:put).and_return(response)
    end

    after do
      config.instance_variable_set(:@conn, nil)
    end

    it 'posts consent payload to the consent endpoint with bearer authorization' do
      result = config.post_consent_update(pid, payload, bearer_token)

      expect(result).to eq(response)
      expect(connection).to have_received(:put).with(
        "#{described_class::VHA_CONSENT_ENDPOINT}/#{pid}",
        payload.to_json,
        hash_including(
          'Authorization' => "Bearer #{bearer_token}",
          'Content-Type' => 'application/json'
        )
      )
    end
  end
end
