# frozen_string_literal: true

require 'rails_helper'
require 'bep/claims/jwt_generator'

RSpec.describe BEP::Claims::JwtGenerator do
  describe '#encode_jwt' do
    it 'returns a token with required fields' do
      encoded_jwt = BEP::Claims::JwtGenerator.encode_jwt
      decoded_jwt = JWT.decode(encoded_jwt, Settings.bep.claims.jwt_secret, true, {
                                 typ: 'JWT',
                                 alg: 'HS256'
                               }).first
      expect(decoded_jwt.keys)
        .to include('iss', 'jti', 'exp', 'iat', 'applicationID', 'userID', 'stationID')
      expect(decoded_jwt['iss']).to eq('vets-api')
      expect(decoded_jwt['applicationID']).to eq('VBMS')
      expect(decoded_jwt['userID']).to eq('VAGOVSYSACCT')
      expect(decoded_jwt['stationID']).to eq('283')
    end
  end
end
