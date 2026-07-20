# frozen_string_literal: true

require 'rails_helper'
require 'bep/awards/jwt_generator'

RSpec.describe BEP::Awards::JwtGenerator do
  describe '#encode_jwt' do
    it 'returns a token with required fields' do
      encoded_jwt = BEP::Awards::JwtGenerator.encode_jwt
      decoded_jwt = JWT.decode(encoded_jwt, Settings.bep.awards.jwt_secret, true, {
                                 typ: 'JWT',
                                 alg: 'HS256'
                               }).first
      expect(decoded_jwt.keys)
        .to include('iss', 'jti', 'exp', 'iat', 'applicationID', 'userID', 'stationID')
      expect(decoded_jwt['iss']).to eq('bip-va-gov')
      expect(decoded_jwt['applicationID']).to eq('VBMS')
      expect(decoded_jwt['userID']).to eq('VAGOVSYSACCT')
      expect(decoded_jwt['stationID']).to eq('283')
    end
  end
end
