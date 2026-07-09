# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SignIn::Webauthn::AuthenticationsController, type: :controller do
  let(:sign_in_logger) { instance_double(SignIn::Logger, info: nil, error: nil) }

  before { allow(SignIn::Logger).to receive(:new).and_return(sign_in_logger) }

  describe 'POST #options' do
    let(:webauthn_options) { { 'challenge' => 'some-challenge' } }
    let(:challenge_id) { 'some-challenge-id' }
    let(:generator) do
      instance_double(SignIn::Webauthn::Authentication::OptionsGenerator, perform: [webauthn_options, challenge_id])
    end

    before do
      allow(SignIn::Webauthn::Authentication::OptionsGenerator).to receive(:new).and_return(generator)
    end

    it 'returns the generated options and challenge id' do
      post :options

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body, symbolize_names: true))
        .to eq(options: { challenge: 'some-challenge' }, challenge_id:)
    end

    it 'logs the options generation' do
      post :options

      expect(sign_in_logger).to have_received(:info).with('webauthn authentication options generated')
    end

    context 'when the generator raises' do
      before { allow(generator).to receive(:perform).and_raise(StandardError, 'options failed') }

      it 'returns an unprocessable entity error' do
        post :options

        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body, symbolize_names: true)).to eq(error: 'options failed')
      end

      it 'logs the failure' do
        post :options

        expect(sign_in_logger).to have_received(:error)
          .with('webauthn authentication options error', exception: instance_of(StandardError))
      end
    end
  end

  describe 'POST #verify' do
    let(:authentication) { { 'attest' => 'some-assertion' } }
    let(:challenge_id) { 'some-challenge-id' }
    let(:user_account) { create(:user_account) }
    let(:session) { instance_double(SignIn::OAuthSession, user_account:) }
    let(:session_container) { instance_double(SignIn::SessionContainer, session:) }
    let(:verifier) { instance_double(SignIn::Webauthn::Authentication::Verifier, perform: session_container) }
    let(:token_serializer) { instance_double(SignIn::TokenSerializer, perform: { access_token: 'some-access-token' }) }

    before do
      allow(SignIn::Webauthn::Authentication::Verifier).to receive(:new).and_return(verifier)
      allow(SignIn::TokenSerializer).to receive(:new).and_return(token_serializer)
    end

    it 'verifies the assertion, serializes tokens, and flags the response verified' do
      post :verify, params: { authentication:, challenge_id: }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body, symbolize_names: true))
        .to eq(access_token: 'some-access-token', verified: true)
    end

    it 'passes the attestation and challenge id to the verifier' do
      post :verify, params: { authentication:, challenge_id: }

      expect(SignIn::Webauthn::Authentication::Verifier).to have_received(:new)
        .with('some-assertion', challenge_id)
    end

    it 'logs the authentication with user account context' do
      post :verify, params: { authentication:, challenge_id: }

      expect(sign_in_logger).to have_received(:info)
        .with('webauthn authentication verified', user_account_id: user_account.id, icn: user_account.icn)
    end

    context 'when verification raises' do
      before { allow(verifier).to receive(:perform).and_raise(StandardError, 'verify failed') }

      it 'returns an unprocessable entity error' do
        post :verify, params: { authentication:, challenge_id: }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body, symbolize_names: true)).to eq(error: 'verify failed')
      end

      it 'logs the failure' do
        post :verify, params: { authentication:, challenge_id: }

        expect(sign_in_logger).to have_received(:error)
          .with('webauthn authentication verify error', exception: instance_of(StandardError))
      end
    end
  end
end
