# frozen_string_literal: true

require 'rails_helper'

describe MebApi::DGI::Forms::Configuration do
  subject(:config) { described_class.instance }

  let(:mock_enabled) { false }

  before do
    allow(Settings.dgi.vets).to receive_messages(
      url: 'https://example.com',
      mock: mock_enabled
    )
  end

  after do
    # Clear the memoized connection to prevent state leakage to other tests
    config.instance_variable_set(:@conn, nil)
  end

  it 'returns base_path' do
    expect(config.base_path).to eq('https://example.com')
  end

  it 'returns service_name' do
    expect(config.service_name).to eq('DGI')
  end

  context 'when mock is disabled' do
    let(:mock_enabled) { false }

    it 'indicates mock is disabled' do
      expect(config).not_to be_mock_enabled
    end
  end

  context 'when mock is enabled' do
    let(:mock_enabled) { true }

    it 'indicates mock is enabled' do
      expect(config).to be_mock_enabled
    end
  end

  it 'memoizes the Faraday connection' do
    first_conn = config.connection
    expect(config.connection).to equal(first_conn)
  end

  describe 'error handling middleware' do
    let(:error_response_body) do
      { code: '_EXT_503', detail: 'External service unavailable', source: 'DGI' }.to_json
    end
    let(:breakers_service) do
      instance_double(Breakers::Service, latest_outage: nil, add_success: nil, add_error: nil,
                                         exception_represents_server_error?: true, name: 'DGI').as_null_object
    end
    let(:breakers_client) do
      instance_double(Breakers::Client, logger: Rails.logger).as_null_object
    end

    before do
      # Stub the Breakers client to prevent outage exceptions
      allow(Breakers).to receive(:client).and_return(breakers_client)
      allow(breakers_client).to receive_messages(service_for_request: breakers_service, plugins: [])
    end

    after do
      # Clear the memoized connection to prevent state leakage
      config.instance_variable_set(:@conn, nil)
    end

    context 'when dgi_meb_rudisill_flow_partition feature flag is enabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:dgi_meb_rudisill_flow_partition).and_return(true)
      end

      it 'uses raise_custom_error middleware with DGI prefix inherited from parent' do
        connection = config.connection
        stub_request(:post, 'https://example.com/forms/submit')
          .to_return(status: 503, body: error_response_body, headers: { 'Content-Type' => 'application/json' })

        expect { connection.post('/forms/submit') }
          .to raise_error(Common::Exceptions::BackendServiceException) { |e|
            expect(e.errors.first[:code]).to eq('DGI_EXT_503')
            expect(e.status_code).to eq(503)
          }
      end
    end

    context 'when dgi_meb_rudisill_flow_partition feature flag is disabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:dgi_meb_rudisill_flow_partition).and_return(false)
      end

      it 'uses standard Faraday::Response::RaiseError inherited from parent' do
        connection = config.connection
        stub_request(:post, 'https://example.com/forms/submit')
          .to_return(status: 503, body: error_response_body, headers: { 'Content-Type' => 'application/json' })

        expect { connection.post('/forms/submit') }.to raise_error(Faraday::ServerError)
      end
    end
  end
end
