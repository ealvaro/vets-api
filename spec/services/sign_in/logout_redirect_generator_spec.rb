# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SignIn::LogoutRedirectGenerator do
  describe '#perform' do
    subject do
      SignIn::LogoutRedirectGenerator.new(credential_type:, client_config:, post_logout_redirect_uri:).perform
    end

    describe '#perform' do
      let(:credential_type) { 'logingov' }
      let(:client_config) { create(:client_config, logout_redirect_uri:) }
      let(:logout_redirect_uri) { 'some-logout-redirect-uri' }
      let(:post_logout_redirect_uri) { nil }

      context 'when logout redirect uri is defined in the client configuration' do
        let(:logout_redirect_uri) { 'some-logout-redirect-uri' }

        context 'and the user is authenticated with login.gov credential' do
          let(:logingov_client_id) { IdentitySettings.logingov.client_id }
          let(:logingov_logout_redirect_uri) { IdentitySettings.logingov.logout_redirect_uri }
          let(:random_seed) { 'some-random-seed' }
          let(:ssl_key) { OpenSSL::PKey::RSA.generate(2048) }
          let(:logout_state_payload) do
            {
              client_id: client_config.client_id,
              logout_redirect: client_config.logout_redirect_uri,
              seed: random_seed
            }
          end
          let(:state) { JWT.encode(logout_state_payload, ssl_key, 'RS256') }
          let(:expected_url_params) do
            {
              client_id: logingov_client_id,
              post_logout_redirect_uri: logingov_logout_redirect_uri,
              state:
            }
          end
          let(:expected_url_host) { IdentitySettings.logingov.oauth_url }
          let(:expected_url_path) { 'openid_connect/logout' }
          let(:expected_url) { "#{expected_url_host}/#{expected_url_path}?#{expected_url_params.to_query}" }

          before do
            allow(SecureRandom).to receive(:hex).and_return(random_seed)
            allow_any_instance_of(SignIn::Logingov::Configuration).to receive(:ssl_key).and_return(ssl_key)
          end

          it 'returns a logout redirect to login.gov logout endpoint with proper params' do
            expect(subject).to eq(expected_url)
          end
        end

        context 'and the user is not authenticated with the login.gov credential' do
          let(:credential_type) { 'idme' }
          let(:expected_url) { URI.parse(logout_redirect_uri).to_s }

          it 'returns a logout redirect properly parsing logout redirect uri' do
            expect(subject).to eq(expected_url)
          end
        end

        context 'and no credential type is provided' do
          let(:credential_type) { nil }
          let(:expected_url) { URI.parse(logout_redirect_uri).to_s }

          it 'returns a logout redirect properly parsing logout redirect uri' do
            expect(subject).to eq(expected_url)
          end
        end
      end

      context 'when logout redirect uri is not defined in the client configuration' do
        let(:logout_redirect_uri) { nil }

        it 'returns nil' do
          expect(subject).to be_nil
        end
      end

      context 'when a post_logout_redirect_uri is provided' do
        let(:logout_redirect_uri) { 'https://login-stg.va.gov/logout' }

        context 'and it shares the domain of the configured logout redirect uri' do
          let(:post_logout_redirect_uri) { 'https://some-site.va.gov/' }
          let(:logout_redirect_uri_with_param) do
            uri = URI.parse(logout_redirect_uri)
            uri.query = { 'post_logout_redirect_uri' => post_logout_redirect_uri }.to_query
            uri.to_s
          end

          context 'and the user is not authenticated with the login.gov credential' do
            let(:credential_type) { 'idme' }

            it 'attaches the post_logout_redirect_uri to the configured logout uri' do
              expect(subject).to eq(logout_redirect_uri_with_param)
            end
          end

          context 'and the user is authenticated with the login.gov credential' do
            let(:credential_type) { 'logingov' }
            let(:logingov_client_id) { IdentitySettings.logingov.client_id }
            let(:logingov_logout_redirect_uri) { IdentitySettings.logingov.logout_redirect_uri }
            let(:random_seed) { 'some-random-seed' }
            let(:ssl_key) { OpenSSL::PKey::RSA.generate(2048) }
            let(:logout_state_payload) do
              {
                client_id: client_config.client_id,
                logout_redirect: logout_redirect_uri_with_param,
                seed: random_seed
              }
            end
            let(:state) { JWT.encode(logout_state_payload, ssl_key, 'RS256') }
            let(:expected_url_params) do
              {
                client_id: logingov_client_id,
                post_logout_redirect_uri: logingov_logout_redirect_uri,
                state:
              }
            end
            let(:expected_url_host) { IdentitySettings.logingov.oauth_url }
            let(:expected_url_path) { 'openid_connect/logout' }
            let(:expected_url) { "#{expected_url_host}/#{expected_url_path}?#{expected_url_params.to_query}" }

            before do
              allow(SecureRandom).to receive(:hex).and_return(random_seed)
              allow_any_instance_of(SignIn::Logingov::Configuration).to receive(:ssl_key).and_return(ssl_key)
            end

            it 'wraps the attached uri in the login.gov logout redirect' do
              expect(subject).to eq(expected_url)
            end
          end
        end

        context 'and it is on a different domain than the configured logout redirect uri' do
          let(:credential_type) { 'idme' }
          let(:post_logout_redirect_uri) { 'https://malicious.example.com/login/signout' }
          let(:expected_url) { URI.parse(logout_redirect_uri).to_s }

          it 'drops the param and returns the configured logout redirect uri' do
            expect(subject).to eq(expected_url)
          end
        end
      end
    end
  end
end
