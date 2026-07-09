# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SignIn::Webauthn::RegistrationsController, type: :controller do
  let(:credential_uuid) { 'some-credential-uuid' }
  let(:user_account) { create(:user_account) }
  let(:user_verification) { create(:idme_user_verification, idme_uuid: credential_uuid, user_account:) }
  let(:client_id) { 'some-client-id' }
  let!(:client_config) { create(:client_config, client_id:) }
  let!(:oauth_session) { create(:oauth_session, client_id:, user_account:, user_verification:) }
  let(:user) { build(:user, :loa3, user_account:, user_verification:, idme_uuid: credential_uuid) }
  let(:access_token) do
    create(:access_token, user_uuid: user.uuid, client_id:, session_handle: oauth_session.handle)
  end
  let(:encoded_access_token) { SignIn::AccessTokenJwtEncoder.new(access_token:).perform }
  let(:sign_in_logger) { instance_double(SignIn::Logger, info: nil, error: nil) }
  let(:expected_log_context) do
    { user_verification_id: user_verification.id, user_account_id: user_account.id, icn: user_account.icn }
  end

  before do
    allow(controller).to receive(:verified_request?).and_return(true)
    allow(SignIn::Logger).to receive(:new).and_return(sign_in_logger)
    request.headers['Authorization'] = "Bearer #{encoded_access_token}"
  end

  describe 'POST #options' do
    let(:webauthn_options) { { 'challenge' => 'some-challenge' } }
    let(:challenge_id) { 'some-challenge-id' }
    let(:generator) do
      instance_double(SignIn::Webauthn::Registration::OptionsGenerator, perform: [webauthn_options, challenge_id])
    end

    before do
      allow(SignIn::Webauthn::Registration::OptionsGenerator)
        .to receive(:new).with(user_verification:).and_return(generator)
    end

    it 'returns the generated options and challenge id' do
      post :options

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body, symbolize_names: true))
        .to eq(options: { challenge: 'some-challenge' }, challenge_id:)
    end

    it 'logs the options generation with user account context' do
      post :options

      expect(sign_in_logger).to have_received(:info)
        .with('webauthn registration options generated', expected_log_context)
    end

    context 'when the generator raises' do
      before { allow(generator).to receive(:perform).and_raise(StandardError, 'options failed') }

      it 'returns an unprocessable entity error' do
        post :options

        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body, symbolize_names: true)).to eq(error: 'options failed')
      end

      it 'logs the failure with user account context' do
        post :options

        expect(sign_in_logger).to have_received(:error).with(
          'webauthn registration options error',
          exception: instance_of(StandardError),
          context: expected_log_context
        )
      end
    end
  end

  describe 'POST #verify' do
    let(:registration) { { 'attest' => 'some-attestation' } }
    let(:challenge_id) { 'some-challenge-id' }
    let(:verifier) { instance_double(SignIn::Webauthn::Registration::Verifier, perform: true) }

    before do
      allow(SignIn::Webauthn::Registration::Verifier).to receive(:new).and_return(verifier)
    end

    it 'verifies the registration and returns the result' do
      post :verify, params: { registration:, challenge_id: }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body, symbolize_names: true)).to eq(verified: true)
    end

    it 'passes the current user verification, registration params, and challenge id to the verifier' do
      post :verify, params: { registration:, challenge_id: }

      expect(SignIn::Webauthn::Registration::Verifier).to have_received(:new)
        .with(current_user_verification: user_verification, registration: anything, challenge_id:)
    end

    it 'logs the registration with user account context' do
      post :verify, params: { registration:, challenge_id: }

      expect(sign_in_logger).to have_received(:info).with('webauthn registration verified', expected_log_context)
    end

    context 'when verification raises' do
      before { allow(verifier).to receive(:perform).and_raise(StandardError, 'verify failed') }

      it 'returns an unprocessable entity error' do
        post :verify, params: { registration:, challenge_id: }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body, symbolize_names: true)).to eq(error: 'verify failed')
      end

      it 'logs the failure with user account context' do
        post :verify, params: { registration:, challenge_id: }

        expect(sign_in_logger).to have_received(:error).with(
          'webauthn registration verify error',
          exception: instance_of(StandardError),
          context: expected_log_context
        )
      end
    end
  end
end
