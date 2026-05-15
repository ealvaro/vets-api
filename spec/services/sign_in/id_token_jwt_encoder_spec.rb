# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SignIn::IdTokenJwtEncoder do
  describe '#perform' do
    subject { SignIn::IdTokenJwtEncoder.new(access_token:).perform }

    let(:access_token) { create(:access_token, client_id:) }
    let(:client_id) { client_config.client_id }
    let(:client_config) { create(:client_config, access_token_attributes:, oidc:) }
    let(:access_token_attributes) { [] }
    let(:oidc) { false }
    let(:decoded_jwt) { JWT.decode(subject, false, nil).first }

    context 'when input object is an access token' do
      let(:expected_sub) { access_token.user_uuid }
      let(:expected_iss) { access_token.issuer }
      let(:expected_azp) { access_token.client_id }
      let(:expected_exp) { access_token.expiration_time.to_i }
      let(:expected_iat) { access_token.created_time.to_i }
      let(:expected_auth_time) { access_token.created_time.to_i }
      let(:expected_aud) { access_token.audience }

      it 'returns an encoded jwt with expected oidc claims' do
        expect(decoded_jwt['sub']).to eq expected_sub
        expect(decoded_jwt['iss']).to eq expected_iss
        expect(decoded_jwt['azp']).to eq expected_azp
        expect(decoded_jwt['exp']).to eq expected_exp
        expect(decoded_jwt['iat']).to eq expected_iat
        expect(decoded_jwt['auth_time']).to eq expected_auth_time
        expect(decoded_jwt['aud']).to eq expected_aud
      end

      context 'when client is not oidc' do
        it 'includes the standard issuer' do
          expect(decoded_jwt['iss']).to eq(SignIn::Constants::AccessToken::ISSUER)
        end
      end

      context 'when client is oidc' do
        let(:oidc) { true }

        it 'includes the oidc issuer' do
          expect(decoded_jwt['iss']).to eq(IdentitySettings.sign_in.oidc_issuer)
        end
      end

      it 'does not include session-specific claims' do
        expect(decoded_jwt['session_handle']).to be_nil
        expect(decoded_jwt['refresh_token_hash']).to be_nil
        expect(decoded_jwt['device_secret_hash']).to be_nil
        expect(decoded_jwt['jti']).to be_nil
      end

      context 'when there are user attributes on the correlated ClientConfig access_token_attributes' do
        let(:access_token_attributes) { %w[first_name last_name] }
        let(:expected_first_name) { access_token.user_attributes['first_name'] }
        let(:expected_last_name) { access_token.user_attributes['last_name'] }

        it 'includes those attributes on the encoded id token' do
          serialized_attributes = decoded_jwt['user_attributes']
          expect(serialized_attributes['first_name']).to eq(expected_first_name)
          expect(serialized_attributes['last_name']).to eq(expected_last_name)
        end
      end

      context 'when nonce is provided' do
        let(:access_token) { create(:access_token, client_id:, nonce: 'test-nonce-value') }

        it 'includes nonce on the encoded id token' do
          expect(decoded_jwt['nonce']).to eq('test-nonce-value')
        end
      end

      context 'when nonce is not provided' do
        it 'does not include nonce on the encoded id token' do
          expect(decoded_jwt['nonce']).to be_nil
        end
      end
    end
  end
end
