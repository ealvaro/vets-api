# frozen_string_literal: true

require 'rails_helper'
require 'vha_notification/service'
require 'vha_notification/configuration'
require 'vha_notification/constants'
require 'vha_notification/jwt_generator'

describe VHANotification::Service do
  subject { described_class.new }

  let(:pid) { '123456789' }
  let(:consent_data) { true }
  let(:base_url) { 'https://example.vha.notification' }
  let(:settings) do
    OpenStruct.new(
      base_url:,
      station_id: '123',
      user_id: 'test-user',
      application_id: 'test-app',
      app_token: 'test-token',
      jwt_secret: 'test-secret',
      source: 'ibm',
      timeout: 30
    )
  end

  before do
    allow(Settings).to receive(:vha_notification).and_return(settings)
    allow(StatsD).to receive(:increment)
    allow(VHANotification::JwtGenerator).to receive(:encode_jwt).and_return('jwt-token')
    if VHANotification::Configuration.instance_variable_defined?(:@conn)
      VHANotification::Configuration.instance_variable_set(:@conn, nil)
    end
  end

  describe 'VHA Notification API Integration' do
    it 'successfully sends MST consent to VHA API' do
      stub_request(:put, "#{base_url}/api/v1/cfapivhanotificationapi/vha-consent-and-enrollment/#{pid}")
        .with(headers: { 'Authorization' => 'Bearer jwt-token' })
        .to_return(status: 200, body: { success: true }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      result = subject.send_mst_consent(pid, consent_data)

      expect(result[:success]).to be true
      expect(result[:response]).to be_present
    end
  end

  describe 'VHA Notification API Error Handling' do
    it 'handles token retrieval errors gracefully' do
      allow(VHANotification::JwtGenerator).to receive(:encode_jwt)
        .and_raise(StandardError.new('JWT generation failed'))

      expect do
        subject.send_mst_consent(pid, consent_data)
      end.to raise_error(VHANotification::ServiceError, VHANotification::Constants::TOKEN_RETRIEVAL_ERROR)
    end
  end

  describe 'VHA Notification API Consent Error' do
    it 'handles consent update errors gracefully' do
      stub_request(:put, "#{base_url}/api/v1/cfapivhanotificationapi/vha-consent-and-enrollment/#{pid}")
        .to_return(status: 500, body: { error: 'server_error' }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      expect do
        subject.send_mst_consent(pid, consent_data)
      end.to raise_error(VHANotification::ServiceError, /#{Regexp.escape(VHANotification::Constants::CONSENT_UPDATE_ERROR)}/)
    end
  end
end
