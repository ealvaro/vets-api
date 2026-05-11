# frozen_string_literal: true

require 'rails_helper'
require 'common/jwt_generator'

RSpec.describe Common::JwtGenerator do
  let(:private_key) { 'shared-secret' }
  let(:fixed_time) { Time.zone.parse('2026-05-01 10:00:00 UTC') }

  describe '.encode_jwt' do
    it 'encodes a token using provided options' do
      token = described_class.encode_jwt(
        issuer: 'fake-issuer',
        user_id: 'fake-user-id',
        station_id: 'fake-station-id',
        private_key:,
        application_id: 'fake-app-id',
        validity_length: 900.seconds
      )

      payload, header = JWT.decode(token, private_key, true, { algorithm: 'HS256', verify_expiration: false })

      expect(header).to include('typ' => 'JWT', 'alg' => 'HS256')
      expect(payload['iss']).to eq('fake-issuer')
      expect(payload['applicationID']).to eq('fake-app-id')
      expect(payload['userID']).to eq('fake-user-id')
      expect(payload['stationID']).to eq('fake-station-id')
    end
  end

  describe '#encode_jwt' do
    before do
      allow(Time.zone).to receive(:now).and_return(fixed_time)
    end

    it 'sets exp based on validity length' do
      generator = described_class.new(
        issuer: 'issuer',
        user_id: 'user',
        station_id: 'station',
        private_key:,
        validity_length: 120.seconds
      )

      token = generator.encode_jwt
      payload, = JWT.decode(token, private_key, true, { algorithm: 'HS256', verify_expiration: false })

      expect(payload['iat']).to eq(fixed_time.to_i)
      expect(payload['exp']).to eq((fixed_time + 120.seconds).to_i)
    end
  end
end
