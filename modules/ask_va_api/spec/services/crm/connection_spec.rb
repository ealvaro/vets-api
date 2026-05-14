# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Crm::Connection do
  subject(:connection) { described_class.new(icn:, token:) }

  let(:icn) { '0001740097' }
  let(:token) { 'test-bearer-token' }
  let(:base_url) { 'https://example.com' }
  let(:veis_api_path) { 'eis/vagov.lob.ava/api' }
  let(:ocp_apim_subscription_key) { 'non-prod-key' }
  let(:e_subscription_key) { 'prod-e-key' }
  let(:s_subscription_key) { 'prod-s-key' }
  let(:service_name) { 'VEIS-API' }

  let(:crm_settings) do
    OpenStruct.new(
      base_url:,
      veis_api_path:,
      ocp_apim_subscription_key:,
      service_name:,
      e_subscription_key:,
      s_subscription_key:
    )
  end

  before do
    allow(Settings.ask_va_api).to receive(:crm_api).and_return(crm_settings)
  end

  describe '#initialize' do
    it 'sets settings from Settings.ask_va_api.crm_api' do
      expect(connection.settings).to eq(crm_settings)
    end

    it 'sets icn' do
      expect(connection.icn).to eq(icn)
    end

    it 'sets token' do
      expect(connection.token).to eq(token)
    end
  end

  describe 'delegated methods' do
    it 'delegates base_url to settings' do
      expect(connection.base_url).to eq(base_url)
    end

    it 'delegates veis_api_path to settings' do
      expect(connection.veis_api_path).to eq(veis_api_path)
    end

    it 'delegates ocp_apim_subscription_key to settings' do
      expect(connection.ocp_apim_subscription_key).to eq(ocp_apim_subscription_key)
    end

    it 'delegates service_name to settings' do
      expect(connection.service_name).to eq(service_name)
    end

    it 'delegates e_subscription_key to settings' do
      expect(connection.e_subscription_key).to eq(e_subscription_key)
    end

    it 'delegates s_subscription_key to settings' do
      expect(connection.s_subscription_key).to eq(s_subscription_key)
    end
  end

  describe '#request' do
    let(:faraday_response) { instance_double(Faraday::Response, status: 200, body: '{}') }
    let(:faraday_connection) { instance_double(Faraday::Connection) }
    let(:organization) { 'ava-qa' }
    let(:endpoint) { 'inquiries' }

    before do
      allow(Faraday).to receive(:new).and_return(faraday_connection)
    end

    context 'when organization is nil' do
      it 'raises an ArgumentError' do
        expect do
          connection.request(method: :get, endpoint:, payload: {}, organization: nil)
        end.to raise_error(ArgumentError, 'organization is required but was nil or blank')
      end
    end

    context 'when organization is an empty string' do
      it 'raises an ArgumentError' do
        expect do
          connection.request(method: :get, endpoint:, payload: {}, organization: '')
        end.to raise_error(ArgumentError, 'organization is required but was nil or blank')
      end
    end

    context 'with a GET request' do
      it 'sends a GET with merged organization and payload as params' do
        payload = { status: 'open' }

        allow(faraday_connection).to receive(:get) do |_uri, _body, &block|
          request = OpenStruct.new(headers: {})
          block&.call(request)
          faraday_response
        end

        connection.request(method: :get, endpoint:, payload:, organization:)

        expect(faraday_connection).to have_received(:get).with(
          "#{veis_api_path}/#{endpoint}",
          { organizationName: organization, status: 'open' }
        )
      end
    end

    context 'with a POST request' do
      it 'sends a POST with JSON-encoded payload' do
        payload = { question: 'test' }

        allow(faraday_connection).to receive(:post) do |_uri, _body, &block|
          request = OpenStruct.new(headers: {})
          block&.call(request)
          faraday_response
        end

        connection.request(method: :post, endpoint:, payload:, organization:)

        expect(faraday_connection).to have_received(:post).with(
          "#{veis_api_path}/#{endpoint}",
          payload.to_json
        )
      end
    end

    context 'with a PATCH request' do
      it 'sends a PATCH with JSON-encoded payload' do
        payload = { question: 'updated' }

        allow(faraday_connection).to receive(:patch) do |_uri, _body, &block|
          request = OpenStruct.new(headers: {})
          block&.call(request)
          faraday_response
        end

        connection.request(method: :patch, endpoint:, payload:, organization:)

        expect(faraday_connection).to have_received(:patch).with(
          "#{veis_api_path}/#{endpoint}",
          payload.to_json
        )
      end
    end

    context 'with a PUT request' do
      it 'sends a PUT with JSON-encoded payload and organization in query string' do
        payload = { question: 'replaced' }

        allow(faraday_connection).to receive(:put) do |_uri, _body, &block|
          request = OpenStruct.new(headers: {})
          block&.call(request)
          faraday_response
        end

        connection.request(method: :put, endpoint:, payload:, organization:)

        expect(faraday_connection).to have_received(:put).with(
          "#{veis_api_path}/#{endpoint}?organizationName=#{organization}",
          payload.to_json
        )
      end
    end

    it 'sets request headers on the request object' do
      allow(Settings).to receive(:vsp_environment).and_return('staging')

      allow(faraday_connection).to receive(:get) do |_uri, _body, &block|
        request = OpenStruct.new(headers: {})
        block.call(request)
        expect(request.headers).to include(
          'Content-Type' => 'application/json',
          'Authorization' => "Bearer #{token}",
          'X-VA-ICN' => icn
        )
        faraday_response
      end

      connection.request(method: :get, endpoint:, payload: {}, organization:)
    end
  end

  describe 'request_headers (via #request)' do
    let(:faraday_connection) { instance_double(Faraday::Connection) }
    let(:faraday_response) { instance_double(Faraday::Response, status: 200, body: '{}') }
    let(:captured_headers) { {} }

    before do
      allow(Faraday).to receive(:new).and_return(faraday_connection)
      allow(faraday_connection).to receive(:get) do |_uri, _body, &block|
        request = OpenStruct.new(headers: {})
        block.call(request)
        captured_headers.merge!(request.headers)
        faraday_response
      end
    end

    context 'when vsp_environment is production' do
      before { allow(Settings).to receive(:vsp_environment).and_return('production') }

      it 'includes production subscription keys' do
        connection.request(method: :get, endpoint: 'test', payload: {}, organization: 'org')

        expect(captured_headers).to include(
          'OCP-APIM-Subscription-Key-E' => e_subscription_key,
          'OCP-APIM-Subscription-Key-S' => s_subscription_key
        )
        expect(captured_headers).not_to have_key('OCP-APIM-Subscription-Key')
      end
    end

    context 'when vsp_environment is Production (mixed case)' do
      before { allow(Settings).to receive(:vsp_environment).and_return('Production') }

      it 'treats it as production due to case-insensitive comparison' do
        connection.request(method: :get, endpoint: 'test', payload: {}, organization: 'org')

        expect(captured_headers).to include(
          'OCP-APIM-Subscription-Key-E' => e_subscription_key,
          'OCP-APIM-Subscription-Key-S' => s_subscription_key
        )
      end
    end

    context 'when vsp_environment is a non-production value' do
      before { allow(Settings).to receive(:vsp_environment).and_return('staging') }

      it 'includes the non-production subscription key' do
        connection.request(method: :get, endpoint: 'test', payload: {}, organization: 'org')

        expect(captured_headers).to include(
          'OCP-APIM-Subscription-Key' => ocp_apim_subscription_key
        )
        expect(captured_headers).not_to have_key('OCP-APIM-Subscription-Key-E')
        expect(captured_headers).not_to have_key('OCP-APIM-Subscription-Key-S')
      end
    end

    context 'when vsp_environment is nil' do
      before { allow(Settings).to receive(:vsp_environment).and_return(nil) }

      it 'falls back to non-production headers' do
        connection.request(method: :get, endpoint: 'test', payload: {}, organization: 'org')

        expect(captured_headers).to include(
          'OCP-APIM-Subscription-Key' => ocp_apim_subscription_key
        )
      end
    end

    it 'always includes base headers' do
      allow(Settings).to receive(:vsp_environment).and_return('staging')
      connection.request(method: :get, endpoint: 'test', payload: {}, organization: 'org')

      expect(captured_headers).to include(
        'Content-Type' => 'application/json',
        'Authorization' => "Bearer #{token}",
        'X-VA-ICN' => icn
      )
    end
  end

  describe 'URI construction' do
    let(:faraday_connection) { instance_double(Faraday::Connection) }
    let(:faraday_response) { instance_double(Faraday::Response, status: 200, body: '{}') }

    before do
      allow(Faraday).to receive(:new).and_return(faraday_connection)
      allow(Settings).to receive(:vsp_environment).and_return('staging')
    end

    it 'builds URI without query string for GET requests' do
      allow(faraday_connection).to receive(:get) do |uri, _body, &block|
        request = OpenStruct.new(headers: {})
        block.call(request)
        expect(uri).to eq("#{veis_api_path}/inquiries")
        faraday_response
      end

      connection.request(method: :get, endpoint: 'inquiries', payload: {}, organization: 'org')
    end

    it 'builds URI without query string for POST requests' do
      allow(faraday_connection).to receive(:post) do |uri, _body, &block|
        request = OpenStruct.new(headers: {})
        block.call(request)
        expect(uri).to eq("#{veis_api_path}/inquiries")
        faraday_response
      end

      connection.request(method: :post, endpoint: 'inquiries', payload: {}, organization: 'org')
    end

    it 'appends organization as query string for PUT requests' do
      allow(faraday_connection).to receive(:put) do |uri, _body, &block|
        request = OpenStruct.new(headers: {})
        block.call(request)
        expect(uri).to eq("#{veis_api_path}/inquiries?organizationName=org")
        faraday_response
      end

      connection.request(method: :put, endpoint: 'inquiries', payload: {}, organization: 'org')
    end
  end

  describe 'Faraday connection configuration' do
    before do
      allow(Settings).to receive(:vsp_environment).and_return('staging')
    end

    it 'configures Faraday with the correct base_url' do
      expect(Faraday).to receive(:new).with(url: base_url).and_call_original

      # Stub the actual HTTP call
      stub_request(:get, /#{base_url}/).to_return(status: 200, body: '{}')
      connection.request(method: :get, endpoint: 'test', payload: {}, organization: 'org')
    end
  end
end
