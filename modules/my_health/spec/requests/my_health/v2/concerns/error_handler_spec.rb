# frozen_string_literal: true

require 'rails_helper'
require 'unified_health_data/medical_records_service'
require 'support/shared_contexts/uhd_security_endpoint'

RSpec.describe MyHealth::V2::Concerns::ErrorHandler, :skip_json_api_validation, type: :request do
  include_context 'uhd legacy security endpoint'

  let(:current_user) { build(:user, :mhv) }
  let(:path) { '/my_health/v2/medical_records/allergies' }

  before do
    Timecop.freeze('2025-06-02T08:00:00Z')
    sign_in_as(current_user)
    allow(Flipper).to receive(:enabled?).with(:mhv_accelerated_delivery_uhd_enabled,
                                              instance_of(User)).and_return(true)
  end

  after do
    Timecop.return
  end

  # Helper to stub service and make request
  def stub_and_request(error)
    allow_any_instance_of(UnifiedHealthData::MedicalRecordsService).to receive(:get_allergies).and_raise(error)
    VCR.use_cassette('unified_health_data/get_allergies_200') do
      get path, headers: { 'X-Key-Inflection' => 'camel' }
    end
  end

  describe 'Datadog span tagging' do
    let(:active_span) { instance_double(Datadog::Tracing::Span).as_null_object }
    let(:rack_span) { instance_double(Datadog::Tracing::Span).as_null_object }
    let(:error) { StandardError.new('something unexpected') }

    before do
      allow(Datadog::Tracing).to receive(:active_span).and_return(active_span)
    end

    it 'tags the active Datadog tracing span with the error' do
      allow_any_instance_of(ActionDispatch::Request).to receive(:env).and_wrap_original do |m, *args|
        env = m.call(*args)
        env[Datadog::Tracing::Contrib::Rack::Ext::RACK_ENV_REQUEST_SPAN] = rack_span
        env
      end

      stub_and_request(error)

      expect(active_span).to have_received(:set_error).with(error)
    end

    it 'tags the Rack request span with the error' do
      allow_any_instance_of(ActionDispatch::Request).to receive(:env).and_wrap_original do |m, *args|
        env = m.call(*args)
        env[Datadog::Tracing::Contrib::Rack::Ext::RACK_ENV_REQUEST_SPAN] = rack_span
        env
      end

      stub_and_request(error)

      expect(rack_span).to have_received(:set_error).with(error)
    end

    it 'does not raise when no active span exists' do
      allow(Datadog::Tracing).to receive(:active_span).and_return(nil)

      stub_and_request(error)

      expect(response).to have_http_status(:internal_server_error)
    end

    it 'does not raise when no Rack span exists in the request env' do
      stub_and_request(error)

      expect(response).to have_http_status(:internal_server_error)
    end
  end

  describe 'status code mapping' do
    context 'when upstream times out (GatewayTimeout)' do
      it 'returns 504' do
        stub_and_request(Common::Exceptions::GatewayTimeout.new('Faraday::TimeoutError'))
        expect(response).to have_http_status(:gateway_timeout)
      end
    end

    context 'when raw Net::HTTP times out (Timeout::Error)' do
      it 'returns 504 for Net::OpenTimeout' do
        stub_and_request(Net::OpenTimeout.new('execution expired'))
        expect(response).to have_http_status(:gateway_timeout)
      end

      it 'returns 504 for Net::ReadTimeout' do
        stub_and_request(Net::ReadTimeout.new('Net::ReadTimeout'))
        expect(response).to have_http_status(:gateway_timeout)
      end
    end

    context 'when connection fails (ClientError with nil status)' do
      it 'returns 503' do
        stub_and_request(Common::Client::Errors::ClientError.new('Connection refused', nil))
        expect(response).to have_http_status(:service_unavailable)
      end
    end

    context 'when upstream returns HTTP error (ClientError with status)' do
      it 'returns 502' do
        stub_and_request(Common::Client::Errors::ClientError.new('Internal Server Error', 500))
        expect(response).to have_http_status(:bad_gateway)
      end
    end

    context 'when BackendServiceException is raised' do
      it 'returns 502' do
        stub_and_request(Common::Exceptions::BackendServiceException.new('VA900', {}, 502, 'Backend failure'))
        expect(response).to have_http_status(:bad_gateway)
      end
    end

    context 'when circuit breaker is open (Breakers::OutageException)' do
      it 'returns 503' do
        mock_service = instance_double(Breakers::Service, name: 'UHD')
        outage = instance_double(Breakers::Outage, start_time: Time.zone.now, end_time: nil, service: mock_service)
        stub_and_request(Breakers::OutageException.new(outage, mock_service))
        expect(response).to have_http_status(:service_unavailable)
      end
    end

    context 'when DNS resolution fails (SocketError)' do
      it 'returns 503' do
        stub_and_request(SocketError.new('getaddrinfo: nodename nor servname provided'))
        expect(response).to have_http_status(:service_unavailable)
      end
    end

    context 'when TLS handshake fails (OpenSSL::SSL::SSLError)' do
      it 'returns 503' do
        stub_and_request(OpenSSL::SSL::SSLError.new('SSL_connect returned=1 errno=0'))
        expect(response).to have_http_status(:service_unavailable)
      end
    end

    context 'when an unexpected StandardError is raised' do
      it 'returns 500' do
        stub_and_request(StandardError.new('something unexpected'))
        expect(response).to have_http_status(:internal_server_error)
      end
    end
  end
end
