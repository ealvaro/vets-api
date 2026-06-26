# frozen_string_literal: true

require 'rails_helper'
require 'sign_in/logingov/service'

RSpec.describe V0::SignIn::LogingovLogoutProxyController, type: :controller do
  describe 'GET logingov_logout_proxy' do
    subject { get(:logingov_logout_proxy, params: logingov_logout_proxy_params) }

    let(:logingov_logout_proxy_params) do
      {}.merge(state)
    end
    let(:state) { { state: state_value } }
    let(:state_value) { 'some-state-value' }
    let!(:client_config) { create(:client_config, client_id:, logout_redirect_uri:) }
    let(:client_id) { 'some-client-id' }
    let(:logout_redirect_uri) { 'https://registered-client.example.com/logout' }

    context 'when state param is not given' do
      let(:state) { {} }
      let(:expected_error_json) { { 'errors' => expected_error } }
      let(:expected_error_status) { :bad_request }
      let(:expected_error_log) { '[SignInService] [V0::SignInController] logingov_logout_proxy error' }
      let(:expected_error_message) do
        { errors: expected_error, error_code: }
      end
      let(:error_code) { SignIn::Constants::ErrorCode::INVALID_REQUEST }
      let(:expected_error) { 'State is not defined' }

      before { allow(Rails.logger).to receive(:info) }

      it 'renders expected error' do
        expect(JSON.parse(subject.body)).to eq(expected_error_json)
      end

      it 'returns expected status' do
        expect(subject).to have_http_status(expected_error_status)
      end

      it 'logs the failed authorize attempt' do
        expect(Rails.logger).to receive(:info).with(expected_error_log, expected_error_message)
        subject
      end
    end

    context 'when state param is given' do
      let(:state_value) { encoded_state }
      let(:ssl_key) { OpenSSL::PKey::RSA.generate(2048) }
      let(:encoded_state) { JWT.encode(state_payload, ssl_key, 'RS256') }
      let(:state_payload) do
        {
          client_id: state_client_id,
          logout_redirect: state_logout_redirect_uri,
          seed: 'some-seed'
        }
      end
      let(:state_client_id) { client_id }
      let(:state_logout_redirect_uri) { logout_redirect_uri }

      before do
        allow_any_instance_of(SignIn::Logingov::Configuration).to receive(:ssl_key).and_return(ssl_key)
      end

      context 'and the state is a valid signed token' do
        it 'returns ok status' do
          expect(subject).to have_http_status(:ok)
        end

        it 'renders the logout redirect uri from the state in the template' do
          expect(subject.body).to include(logout_redirect_uri)
        end
      end

      context 'and the state cannot be decoded' do
        let(:state_value) { 'not-a-valid-jwt' }

        it 'returns bad request status' do
          expect(subject).to have_http_status(:bad_request)
        end
      end

      context 'and the logout_redirect does not match the registered client redirect uri' do
        let(:state_logout_redirect_uri) { 'https://attacker.example.com/logout' }

        it 'returns bad request status' do
          expect(subject).to have_http_status(:bad_request)
        end

        it 'does not render the unregistered redirect uri' do
          expect(subject.body).not_to include('attacker.example.com')
        end
      end

      context 'and the state references a client_id with no configuration' do
        let(:state_client_id) { 'unregistered-client-id' }

        it 'returns bad request status' do
          expect(subject).to have_http_status(:bad_request)
        end
      end

      context 'and the state has a post_logout_redirect_uri' do
        let(:logout_redirect_uri) { 'https://login-stg.va.gov/oauth2/v1/logout' }
        let(:post_logout_redirect_uri) { 'https://login-stg.va.gov/oauth2/v1/logout?fromURI=some-from-uri' }
        let(:logingov_logout_url) do
          SignIn::LogoutRedirectGenerator.new(
            client_config:,
            credential_type: SignIn::Constants::Auth::LOGINGOV,
            post_logout_redirect_uri:
          ).perform
        end
        let(:state_value) { Rack::Utils.parse_query(URI.parse(logingov_logout_url).query)['state'] }

        it 'renders the post_logout_redirect_uri with its query preserved' do
          expect(subject).to have_http_status(:ok)
          expect(subject.body).to include('fromURI')
        end
      end
    end
  end
end
