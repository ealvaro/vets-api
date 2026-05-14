# frozen_string_literal: true

require 'rails_helper'
require 'vha_notification/jwt_generator'

RSpec.describe VHANotification::JwtGenerator do
  let(:jwt_secret) { 'test-jwt-secret' }
  let(:issuer) { 'vha-notify-issuer' }
  let(:user_id) { 'vha-user-123' }
  let(:station_id) { '123' }
  let(:application_id) { 'vha-notify-app' }

  before do
    allow(Settings).to receive(:vha_notification).and_return(
      OpenStruct.new(
        jwt_secret:,
        issuer:,
        user_id:,
        station_id:,
        application_id:
      )
    )
  end

  describe '.encode_jwt' do
    it 'delegates to a new instance' do
      generator = instance_double(described_class, encode_jwt: 'encoded-jwt')
      allow(described_class).to receive(:new).and_return(generator)

      expect(described_class.encode_jwt).to eq('encoded-jwt')
    end
  end

  describe '#encode_jwt' do
    let(:generator) { described_class.new }
    let(:fixed_time) { Time.zone.parse('2026-04-27 12:00:00 UTC') }

    before do
      allow(Time.zone).to receive(:now).and_return(fixed_time)
    end

    it 'delegates token generation to Common::JwtGenerator with VHA claims and defaults' do
      expect(Common::JwtGenerator).to receive(:encode_jwt).with(
        issuer:,
        private_key: jwt_secret,
        user_id:,
        station_id:,
        application_id:
      ).and_call_original

      generator.encode_jwt
    end

    it 'encodes a token with expected header and payload claims' do
      token = generator.encode_jwt
      payload, header = JWT.decode(
        token,
        jwt_secret,
        true,
        { algorithm: Common::JwtGenerator::DEFAULT_ALGORITHM, verify_expiration: false }
      )

      expect(header).to include('typ' => 'JWT', 'alg' => Common::JwtGenerator::DEFAULT_ALGORITHM)
      expect(payload['iss']).to eq(issuer)
      expect(payload['applicationID']).to eq(application_id)
      expect(payload['userID']).to eq(user_id)
      expect(payload['stationID']).to eq(station_id)
      expect(payload['jti']).to match(/\A[0-9a-f-]{36}\z/)
    end

    it 'sets token expiration to validity length after iat' do
      token = generator.encode_jwt
      payload, = JWT.decode(
        token,
        jwt_secret,
        true,
        { algorithm: Common::JwtGenerator::DEFAULT_ALGORITHM, verify_expiration: false }
      )

      expect(payload['iat']).to eq(fixed_time.to_i)
      expect(payload['exp']).to eq((fixed_time + Common::JwtGenerator::DEFAULT_VALIDITY_LENGTH).to_i)
      expect(payload['exp'] - payload['iat']).to eq(Common::JwtGenerator::DEFAULT_VALIDITY_LENGTH.to_i)
    end

    it 'coerces integer settings to strings at runtime' do
      allow(Settings).to receive(:vha_notification).and_return(
        OpenStruct.new(
          jwt_secret:,
          issuer: 0,
          user_id: 10,
          station_id: 20,
          application_id: 30
        )
      )

      token = generator.encode_jwt
      payload, = JWT.decode(
        token,
        jwt_secret,
        true,
        { algorithm: Common::JwtGenerator::DEFAULT_ALGORITHM, verify_expiration: false }
      )

      expect(payload['iss']).to eq('0')
      expect(payload['applicationID']).to eq('30')
      expect(payload['userID']).to eq('10')
      expect(payload['stationID']).to eq('20')
    end

    it 'raises a clear error when required settings are missing' do
      allow(Settings).to receive(:vha_notification).and_return(
        OpenStruct.new(
          jwt_secret:,
          issuer: nil,
          user_id:,
          station_id:,
          application_id:
        )
      )

      expect { generator.encode_jwt }
        .to raise_error(ArgumentError, /Settings\.vha_notification\.issuer must be present/)
    end
  end
end
