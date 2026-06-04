# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SignIn::StatePayloadJwtDecoder do
  describe '#perform' do
    subject do
      SignIn::StatePayloadJwtDecoder.new(state_payload_jwt:).perform
    end

    let(:state_payload_jwt) do
      SignIn::StatePayloadJwtEncoder.new(acr:,
                                         client_config:,
                                         code_challenge_method:,
                                         type:,
                                         code_challenge:,
                                         client_state:,
                                         scope:,
                                         operation:,
                                         nonce:,
                                         redirect_uri:,
                                         authorize_sso_id:).perform
    end
    let(:code_challenge) { Base64.urlsafe_encode64('some-safe-code-challenge') }
    let(:code_challenge_method) { SignIn::Constants::Auth::CODE_CHALLENGE_METHOD }
    let(:client_state) { SecureRandom.alphanumeric(client_state_minimum_length + 1) }
    let(:acr) { SignIn::Constants::Auth::ACR_VALUES.first }
    let(:type) { SignIn::Constants::Auth::CSP_TYPES.first }
    let(:client_id) { client_config.client_id }
    let(:client_config) { create(:client_config, shared_sessions:) }
    let(:created_at) { Time.zone.now.to_i }
    let(:shared_sessions) { true }
    let(:scope) { SignIn::Constants::Auth::DEVICE_SSO }
    let(:operation) { SignIn::Constants::Auth::VERIFY_CTA_AUTHENTICATED }
    let(:nonce) { nil }
    let(:redirect_uri) { nil }
    let(:authorize_sso_id) { nil }

    let(:client_state_minimum_length) { SignIn::Constants::Auth::CLIENT_STATE_MINIMUM_LENGTH }

    context 'when state payload jwt is encoded with a different signature than expected' do
      let(:state_payload_jwt) do
        JWT.encode(
          jwt_payload,
          OpenSSL::PKey::RSA.new(2048),
          SignIn::Constants::Auth::JWT_ENCODE_ALGORITHM
        )
      end

      let(:jwt_payload) do
        {
          code_challenge:,
          client_state:,
          acr:,
          type:,
          client_id:,
          created_at:,
          scope:,
          operation:,
          redirect_uri:,
          authorize_sso_id:
        }
      end
      let(:expected_error) { SignIn::Errors::StatePayloadSignatureMismatchError }
      let(:expected_error_message) { 'State JWT body does not match signature' }

      it 'returns a JWT signature mismatch error' do
        expect { subject }.to raise_error(expected_error, expected_error_message)
      end
    end

    context 'when state payload jwt is malformed' do
      let(:state_payload_jwt) { 'some-messed-up-jwt' }
      let(:expected_error) { SignIn::Errors::StatePayloadMalformedJWTError }
      let(:expected_error_message) { 'State JWT is malformed' }

      it 'raises a malformed jwt error' do
        expect { subject }.to raise_error(expected_error, expected_error_message)
      end
    end

    context 'when state payload jwt is valid' do
      it 'returns a State Payload with expected attributes' do
        decoded_state_payload = subject
        expect(decoded_state_payload.code_challenge).to eq(code_challenge)
        expect(decoded_state_payload.client_state).to eq(client_state)
        expect(decoded_state_payload.acr).to eq(acr)
        expect(decoded_state_payload.type).to eq(type)
        expect(decoded_state_payload.client_id).to eq(client_id)
        expect(decoded_state_payload.created_at).to eq(created_at)
        expect(decoded_state_payload.scope).to eq(scope)
        expect(decoded_state_payload.operation).to eq(operation)
        expect(decoded_state_payload.nonce).to eq(nonce)
        expect(decoded_state_payload.redirect_uri).to eq(redirect_uri)
        expect(decoded_state_payload.authorize_sso_id).to eq(authorize_sso_id)
      end
    end

    context 'when state payload jwt includes nonce' do
      let(:nonce) { 'test-nonce-value' }

      it 'returns a State Payload with nonce' do
        decoded_state_payload = subject
        expect(decoded_state_payload.nonce).to eq('test-nonce-value')
      end
    end

    context 'when state payload jwt includes redirect_uri' do
      let(:redirect_uri) { 'https://review-instance.example.com/v0/sign_in/callback' }

      it 'returns a State Payload with redirect_uri' do
        decoded_state_payload = subject
        expect(decoded_state_payload.redirect_uri).to eq(redirect_uri)
      end
    end

    context 'when state payload jwt includes authorize_sso_id' do
      let(:authorize_sso_id) { SecureRandom.uuid }

      it 'returns a State Payload with authorize_sso_id' do
        decoded_state_payload = subject
        expect(decoded_state_payload.authorize_sso_id).to eq(authorize_sso_id)
      end
    end
  end
end
