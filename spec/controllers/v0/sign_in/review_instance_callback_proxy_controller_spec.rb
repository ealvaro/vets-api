# frozen_string_literal: true

require 'rails_helper'

RSpec.describe V0::SignIn::ReviewInstanceCallbackProxyController, type: :controller do
  describe 'GET review_instance_callback_proxy' do
    subject { get(:review_instance_callback_proxy, params:) }

    let(:code_value) { 'some-code' }
    let(:redirect_uri) { 'https://review-instance.example.com/v0/sign_in/callback' }
    let(:meta_refresh_tag) { '<meta http-equiv="refresh" content="0;' }

    let(:client_config) { create(:client_config) }
    let(:code_challenge) { Base64.urlsafe_encode64(SecureRandom.hex) }
    let(:valid_state) do
      SignIn::StatePayloadJwtEncoder.new(
        code_challenge:,
        code_challenge_method: SignIn::Constants::Auth::CODE_CHALLENGE_METHOD,
        acr: SignIn::Constants::Auth::LOA3,
        client_config:,
        type: SignIn::Constants::Auth::IDME,
        operation: SignIn::Constants::Auth::AUTHORIZE,
        redirect_uri:
      ).perform
    end

    shared_examples 'error response' do
      it 'returns bad request' do
        expect(subject).to have_http_status(:bad_request)
      end

      it 'renders expected error' do
        expect(JSON.parse(subject.body)).to eq({ 'errors' => expected_error })
      end
    end

    context 'when state is arbitrary' do
      let(:params) { { code: code_value, state: 'some-arbitrary-state' } }
      let(:expected_error) { 'State JWT is malformed' }

      it_behaves_like 'error response'
    end

    context 'when state is a JWT but with improper signature' do
      let(:params) { { code: code_value, state: JWT.encode({ data: 'some-data' }, 'wrong-secret', 'HS256') } }
      let(:expected_error) { 'State JWT is malformed' }

      it_behaves_like 'error response'
    end

    context 'when state is missing' do
      let(:params) { { code: code_value } }
      let(:expected_error) { 'State is not defined' }

      it_behaves_like 'error response'
    end

    context 'when state is a proper, expected JWT' do
      let(:params) { { code: code_value, state: valid_state } }

      context 'when redirect_uri is missing from state payload' do
        let(:redirect_uri) { nil }
        let(:expected_error) { 'Redirect URI is not defined' }

        it_behaves_like 'error response'
      end

      it 'returns ok status' do
        expect(subject).to have_http_status(:ok)
      end

      it 'renders a meta refresh tag' do
        expect(subject.body).to include(meta_refresh_tag)
      end

      it 'redirects to the review instance redirect_uri' do
        expect(subject.body).to include(redirect_uri)
      end

      it 'includes the code param' do
        expect(subject.body).to include("code=#{code_value}")
      end

      it 'includes the state param' do
        expect(subject.body).to include("state=#{valid_state}")
      end

      it 'does not include the error param' do
        expect(subject.body).not_to include('error=')
      end

      context 'when error is given instead of code' do
        let(:params) { { error: 'access_denied', state: valid_state } }

        it 'includes the error param' do
          expect(subject.body).to include('error=access_denied')
        end
      end
    end
  end
end
