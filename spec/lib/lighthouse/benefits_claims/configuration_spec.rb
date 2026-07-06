# frozen_string_literal: true

require 'rails_helper'
require 'common/client/configuration/rest'
require 'lighthouse/benefits_claims/configuration'

RSpec.describe BenefitsClaims::Configuration do
  let(:base) { Common::Client::Configuration::REST }
  let(:config) { described_class.send(:new) }
  let(:access_token_settings) do
    Config::Options.new(
      client_id: 'default-client-id',
      rsa_key: 'path/to/default.pem',
      aud_claim_url: 'https://sandbox-api.va.gov'
    )
  end
  let(:benefits_claims_settings) do
    Config::Options.new(
      host: 'https://sandbox-api.va.gov',
      timeout: 30,
      breakers_error_threshold: 90,
      use_mocks: false,
      verify_ssl: true,
      access_token: access_token_settings
    )
  end
  let(:auth_settings) do
    Config::Options.new(
      client_credentials: { verify_ssl: false }
    )
  end

  before do
    allow(Settings.lighthouse).to receive_messages({
                                                     benefits_claims: benefits_claims_settings,
                                                     auth: auth_settings
                                                   })
  end

  context 'valid settings' do
    it 'returns settings' do
      expect(config.settings).to eq(benefits_claims_settings)
    end

    it 'has correct api_key' do
      expect(config.settings.api_key).to eq(benefits_claims_settings.api_key)
    end

    it 'returns base_path' do
      valid_path = 'https://sandbox-api.va.gov'
      expect(config.base_path).to eq(valid_path)
    end

    it 'returns base_api_path' do
      valid_path = 'https://sandbox-api.va.gov/services/claims/v2/veterans'
      expect(config.base_api_path).to eq(valid_path)
    end

    it 'returns use_mocks' do
      expect(config.use_mocks?).to eq(benefits_claims_settings.use_mocks)
    end

    it 'returns verify_ssl' do
      expect(config.verify_ssl?).to eq(benefits_claims_settings.verify_ssl)
    end

    it 'returns breakers_error_threshold' do
      expect(config.breakers_error_threshold).to eq(benefits_claims_settings.breakers_error_threshold)
    end

    it 'returns expected get_access_token?' do
      allow(Settings.betamocks).to receive(:recording).and_return(false)

      get_access_token = config.send(:get_access_token?)
      expect(get_access_token).to be(true) # !use_mocks? || Settings.betamocks.recording
    end
  end

  context 'expected constants' do
    it 'returns service_name' do
      expect(config.service_name).to eq('BenefitsClaims')
    end

    it 'returns breakers_error_threshold' do
      allow(Settings.lighthouse.benefits_claims).to receive(:breakers_error_threshold).and_return(nil)
      expect(config.breakers_error_threshold).to eq(80)
    end

    it 'returns verify_ssl? as true when nil' do
      allow(Settings.lighthouse.benefits_claims).to receive(:verify_ssl).and_return(nil)
      expect(config.verify_ssl?).to be(true)
    end

    it 'returns use_mocks? as false when nil' do
      allow(Settings.lighthouse.benefits_claims).to receive(:use_mocks).and_return(nil)
      expect(config.use_mocks?).to be(false)
    end
  end

  context 'access_token' do
    it 'returns an access token' do
      allow(Settings.betamocks).to receive(:recording).and_return(false)
      allow_any_instance_of(Auth::ClientCredentials::Service).to receive(:get_token).and_return('some-access-token')

      access_token = config.send(:access_token, 'client-id', 'path/to/key.pem', aud_claim_url: 'https://sandbox-api.va.gov')
      expect(access_token).to eq('some-access-token')
    end

    it 'returns nil when use_mocks? is true and Settings.betamocks.recording is false' do
      allow(Settings.lighthouse.benefits_claims).to receive(:use_mocks).and_return(true)
      allow(Settings.betamocks).to receive(:recording).and_return(false)

      access_token = config.send(:access_token, 'client-id', 'path/to/key.pem', aud_claim_url: 'https://sandbox-api.va.gov')
      expect(access_token).to be_nil
    end
  end

  context 'connection' do
    it 'returns existing connection' do
      config.instance_variable_set(:@conn, 'TEST')

      expect(Faraday).not_to receive(:new)
      expect(config.connection).to eq('TEST')
    end

    it 'returns a Faraday connection' do
      conn = config.connection
      expect(conn).to be_a(Faraday::Connection)
      expect(conn.headers).to include('Accept' => 'application/json')
      expect(conn.ssl.verify).to eq(benefits_claims_settings.verify_ssl)
      expect(conn.options.timeout).to eq(benefits_claims_settings.timeout)
      expect(conn.url_prefix).to eq(URI.parse(config.base_api_path))
    end

    it 'performs a GET request' do
      conn = config.connection
      expect(conn).to receive(:get)
      expect(config).to receive(:access_token).and_return('some-access-token')
      config.get('/some_endpoint')
    end

    it 'performs a POST request' do
      conn = config.connection
      expect(conn).to receive(:post)
      expect(config).to receive(:access_token).and_return('some-access-token')
      config.post('/some_endpoint', anything)
    end

    it 'performs a POST request, with params' do
      conn = config.connection
      expect(config).to receive(:access_token).and_return('some-access-token')

      body = { some: 'body' }
      params = { some: 'param' }
      headers = {}
      request = instance_double(Faraday::Request, headers:)

      expect(request).to receive(:body=).with(body)
      expect(request).to receive(:params=).with(params)
      expect(conn).to receive(:post).with('/some_endpoint').and_yield(request)

      config.post_with_params('/some_endpoint', body, params)
      expect(headers['Authorization']).to eq('Bearer some-access-token')
    end
  end
end
