# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TravelClaim::Configuration do
  subject { described_class.instance }

  describe '#request_options' do
    it 'uses travel_pay Faraday timeout defaults' do
      expect(subject.request_options).to eq(open_timeout: 15, timeout: 90)
    end

    it 'applies the timeouts on Faraday connections' do
      connection = subject.connection

      expect(connection.options.open_timeout).to eq(15)
      expect(connection.options.timeout).to eq(90)
    end

    context 'with custom timeout settings' do
      before do
        allow(Settings.check_in.travel_reimbursement_api_v2).to receive_messages(open_timeout: 20, timeout: 120)
      end

      it 'uses the custom timeout values' do
        expect(subject.request_options).to eq(open_timeout: 20, timeout: 120)
      end
    end
  end

  describe '#service_name' do
    it 'has a service name' do
      expect(subject.service_name).to eq('BTSSS-API')
    end
  end

  describe '#breakers_service' do
    it 'is registered on the global Breakers client' do
      expect(Breakers.client.services).to include(subject.breakers_service)
    end

    it 'uses the BTSSS service name' do
      expect(subject.breakers_service.name).to eq('BTSSS-API')
    end
  end

  describe '#base_path' do
    it 'has a base path' do
      expect(subject.base_path).to be_present
      expect(subject.base_path).to be_a(String)
    end

    it 'combines claims_url_v2 and claims_base_path_v2 when both are present' do
      allow(Settings.check_in.travel_reimbursement_api_v2).to receive_messages(
        claims_url_v2: 'https://example.com',
        claims_base_path_v2: 'eis/api/btsss/travelclaim'
      )

      expect(subject.base_path).to eq('https://example.com/eis/api/btsss/travelclaim')
    end

    it 'returns only claims_url_v2 when claims_base_path_v2 is blank' do
      allow(Settings.check_in.travel_reimbursement_api_v2).to receive_messages(
        claims_url_v2: 'https://example.com',
        claims_base_path_v2: ''
      )

      expect(subject.base_path).to eq('https://example.com')
    end
  end

  describe '#connection' do
    it 'has a connection' do
      expect(subject.connection).to be_an_instance_of(Faraday::Connection)
    end

    it 'configures the connection with proper middleware' do
      connection = subject.connection

      # Check that JSON middleware is configured
      expect(connection.builder.handlers.map(&:name)).to include('Faraday::Request::Json')
      expect(connection.builder.handlers.map(&:name)).to include('Faraday::Response::Json')
    end

    it 'uses the correct base URL' do
      # Faraday preserves the URL as-is when it includes path segments
      expect(subject.connection.url_prefix.to_s).to eq(subject.base_path)
    end
  end

  describe 'singleton behavior' do
    it 'returns the same instance' do
      instance1 = described_class.instance
      instance2 = described_class.instance

      expect(instance1).to be(instance2)
    end
  end

  describe 'inheritance' do
    it 'inherits from Common::Client::Configuration::REST' do
      expect(described_class.superclass).to eq(Common::Client::Configuration::REST)
    end

    it 'includes Singleton' do
      expect(described_class.included_modules).to include(Singleton)
    end
  end

  describe '#mock_enabled?' do
    context 'when flipper flag is enabled' do
      before do
        allow(Flipper).to receive(:enabled?).with('check_in_experience_mock_enabled').and_return(true)
      end

      it 'returns true' do
        expect(subject.send(:mock_enabled?)).to be true
      end
    end

    context 'when flipper flag is disabled' do
      before do
        allow(Flipper).to receive(:enabled?).with('check_in_experience_mock_enabled').and_return(false)
      end

      it 'returns false' do
        expect(subject.send(:mock_enabled?)).to be false
      end
    end
  end
end
