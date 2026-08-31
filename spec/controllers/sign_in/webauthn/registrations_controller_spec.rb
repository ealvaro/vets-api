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

  describe 'GET index' do
    context 'when the user has passkeys' do
      let(:credential) { create(:webauthn_credential) }
      let!(:passkey_verification) do
        create(:user_verification, user_account:, webauthn_credential: credential, idme_uuid: nil)
      end

      let(:second_credential) { create(:webauthn_credential) }
      let!(:second_passkey_verification) do
        create(:user_verification, user_account:, webauthn_credential: second_credential, idme_uuid: nil)
      end

      let(:other_user_account) { create(:user_account) }
      let(:other_credential) { create(:webauthn_credential) }
      let!(:other_passkey_verification) do
        create(:user_verification,
               user_account: other_user_account,
               webauthn_credential: other_credential,
               idme_uuid: nil)
      end

      it "returns only the current user's credentials" do
        get :index

        expect(response).to have_http_status(:ok)
        ids = JSON.parse(response.body)['webauthn_credentials'].pluck('credential_id')
        expect(ids).to contain_exactly(credential.credential_id, second_credential.credential_id)
        expect(ids).not_to include(other_credential.credential_id)
      end

      it 'returns only the non-sensitive fields' do
        get :index

        credential_json = JSON.parse(response.body)['webauthn_credentials'].first
        expect(credential_json.keys).to match_array(%w[credential_id aaguid created_at last_used_at])
      end

      it 'logs the listing with user account context' do
        get :index

        expect(sign_in_logger).to have_received(:info)
          .with('webauthn registrations listed', expected_log_context)
      end
    end

    context 'when the user has a revoked passkey' do
      let(:credential) { create(:webauthn_credential) }
      let!(:passkey_verification) do
        create(:user_verification, user_account:, webauthn_credential: credential, idme_uuid: nil)
      end

      let(:revoked_credential) { create(:webauthn_credential, revoked_at: Time.zone.now) }
      let!(:revoked_passkey_verification) do
        create(:user_verification, user_account:, webauthn_credential: revoked_credential, idme_uuid: nil)
      end

      it 'returns only the active credentials' do
        get :index

        ids = JSON.parse(response.body)['webauthn_credentials'].pluck('credential_id')
        expect(ids).to eq([credential.credential_id])
        expect(ids).not_to include(revoked_credential.credential_id)
      end
    end

    context 'when the user has no passkeys' do
      it 'returns an empty collection' do
        get :index

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)['webauthn_credentials']).to eq([])
      end
    end
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

  describe 'DELETE #destroy' do
    subject(:revoke_passkey) { delete :destroy, params: { credential_id: } }

    let(:webauthn_handle) { 'some-webauthn-handle' }
    let(:webauthn_credential) { create(:webauthn_credential) }
    let!(:webauthn_verification) do
      create(:user_verification, user_account:, webauthn_credential:, idme_uuid: nil)
    end
    let(:credential_id) { webauthn_credential.credential_id }
    let(:parsed_body) { JSON.parse(response.body, symbolize_names: true) }

    before do
      user_account.update!(webauthn_handle:)
    end

    it 'revokes the credential' do
      expect { revoke_passkey }.to change { webauthn_credential.reload.revoked_at }.from(nil)
      expect(response).to have_http_status(:ok)
    end

    it 'does not destroy any records' do
      expect { revoke_passkey }.to not_change(UserVerification, :count)
        .and not_change(SignIn::WebauthnCredential, :count)
    end

    it 'returns the signal payload with the remaining active credential ids' do
      other_credential = create(:webauthn_credential)
      create(:user_verification, user_account:, webauthn_credential: other_credential, idme_uuid: nil)

      revoke_passkey

      expect(parsed_body).to eq(
        rp_id: WebAuthn.configuration.rp_id,
        user_id: webauthn_handle,
        all_accepted_credential_ids: [other_credential.credential_id]
      )
    end

    it 'returns an empty accepted list when the last passkey is revoked' do
      revoke_passkey

      expect(parsed_body[:all_accepted_credential_ids]).to eq([])
    end

    it 'logs the revocation with user account context' do
      revoke_passkey

      expect(sign_in_logger).to have_received(:info).with('webauthn registration revoked', expected_log_context)
    end

    context 'with sessions created by the passkey' do
      let!(:passkey_session) do
        create(:oauth_session, client_id:, user_account:, user_verification: webauthn_verification)
      end

      it 'destroys the sessions and signs out their session records' do
        session_record = create(:session_record, handle: passkey_session.handle, user_account:)

        revoke_passkey

        expect(SignIn::OAuthSession.find_by(id: passkey_session.id)).to be_nil
        expect(session_record.reload.signed_out_at).not_to be_nil
      end

      it 'leaves sessions from other credentials intact' do
        revoke_passkey

        expect(SignIn::OAuthSession.find_by(id: oauth_session.id)).to be_present
      end
    end

    context 'when the credential is already revoked' do
      before do
        webauthn_credential.update!(revoked_at: Time.zone.now)
      end

      it 'returns not found' do
        revoke_passkey

        expect(response).to have_http_status(:not_found)
        expect(parsed_body).to eq(error: 'Credential not found')
      end
    end

    context 'when the credential belongs to another account' do
      let(:other_credential) { create(:webauthn_credential) }
      let!(:other_verification) { create(:user_verification, webauthn_credential: other_credential, idme_uuid: nil) }
      let(:credential_id) { other_credential.credential_id }

      it 'returns not found and does not revoke the credential' do
        revoke_passkey

        expect(response).to have_http_status(:not_found)
        expect(other_credential.reload.revoked_at).to be_nil
      end
    end

    context 'when the credential does not exist' do
      let(:credential_id) { 'nonexistent-credential-id' }

      it 'returns not found' do
        revoke_passkey

        expect(response).to have_http_status(:not_found)
        expect(parsed_body).to eq(error: 'Credential not found')
      end
    end

    context 'when revocation raises an unexpected error' do
      before do
        allow(SignIn::SessionRecord).to receive(:sign_out).and_raise(StandardError, 'revoke failed')
      end

      it 'returns an internal server error and rolls back the revocation' do
        revoke_passkey

        expect(response).to have_http_status(:internal_server_error)
        expect(webauthn_credential.reload.revoked_at).to be_nil
      end
    end
  end
end
