# frozen_string_literal: true

require 'rails_helper'
require 'common/client/configuration/rest'
require 'lighthouse/auth/client_credentials/configuration'

RSpec.describe Auth::ClientCredentials::Configuration do
  let(:base) { Common::Client::Configuration::REST }
  let(:config) { described_class.send(:new) }
  let(:auth_settings) do
    Config::Options.new(
      client_credentials: Config::Options.new(verify_ssl: false, breakers_error_threshold: 50)
    )
  end

  before do
    allow(Settings.lighthouse).to receive(:auth).and_return(auth_settings)
  end

  context 'valid settings' do
    it 'returns settings' do
      expect(config.settings).to eq(auth_settings.client_credentials)
    end

    it 'returns verify_ssl' do
      expect(config.verify_ssl?).to eq(auth_settings.client_credentials.verify_ssl)
    end

    it 'returns breakers_error_threshold' do
      expect(config.breakers_error_threshold).to eq(auth_settings.client_credentials.breakers_error_threshold)
    end
  end

  context 'expected constants' do
    it 'returns breakers_error_threshold' do
      allow(Settings.lighthouse.auth.client_credentials).to receive(:breakers_error_threshold).and_return(nil)
      expect(config.breakers_error_threshold).to eq(80)
    end

    it 'returns verify_ssl? as true when nil' do
      allow(Settings.lighthouse.auth.client_credentials).to receive(:verify_ssl).and_return(nil)
      expect(config.verify_ssl?).to be(true)
    end
  end

  describe 'connection' do
    it 'returns existing connection' do
      config.instance_variable_set(:@conn, 'TEST')

      expect(Faraday).not_to receive(:new)
      expect(config.connection).to eq('TEST')
    end

    it 'returns a Faraday connection' do
      conn = config.connection
      expect(conn).to be_a(Faraday::Connection)
      expect(conn.headers).to include('Accept' => 'application/json')
      expect(conn.ssl.verify).to eq(auth_settings.client_credentials.verify_ssl)
      expect(conn.options.timeout).to eq(20) # default read_timeout
    end
  end

  describe 'get_access_token' do
    it 'returns a Faraday::Response' do
      url = 'https://example.com/token'
      body = { test: 'client_credentials' }
      conn = config.connection

      expect(URI).to receive(:encode_www_form).with(body).and_return('test=client_credentials')
      expect(conn).to receive(:post).with(url, 'test=client_credentials')

      config.get_access_token(url, body)
    end
  end
end
