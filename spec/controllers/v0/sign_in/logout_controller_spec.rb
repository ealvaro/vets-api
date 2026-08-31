# frozen_string_literal: true

require 'rails_helper'

RSpec.describe V0::SignIn::LogoutController, type: :controller do
  describe 'GET logout' do
    subject { get(:logout, params: logout_params) }

    let(:logout_params) do
      {}.merge(client_id)
    end
    let(:client_id) { { client_id: client_id_value } }
    let(:client_id_value) { client_config.client_id }
    let!(:client_config) { create(:client_config, logout_redirect_uri:) }
    let(:logout_redirect_uri) { 'https://some-logout-redirect-uri.com' }
    let(:post_logout_redirect_uri) { nil }
    let(:access_token) { SignIn::AccessTokenJwtEncoder.new(access_token: access_token_object).perform }
    let(:authorization) { "Bearer #{access_token}" }
    let(:created_at) { 1.day.ago }
    let(:oauth_session) { create(:oauth_session, user_verification:, created_at:) }
    let(:user_verification) { create(:user_verification) }
    let(:access_token_object) do
      create(:access_token, session_handle: oauth_session.handle, client_id: client_config.client_id, expiration_time:)
    end
    let(:expiration_time) { Time.zone.now + SignIn::Constants::AccessToken::VALIDITY_LENGTH_SHORT_MINUTES }
    let(:expected_cleared_cookies) do
      {
        SignIn::Constants::Auth::ACCESS_TOKEN_COOKIE_NAME => nil,
        SignIn::Constants::Auth::REFRESH_TOKEN_COOKIE_NAME => nil,
        SignIn::Constants::Auth::ANTI_CSRF_COOKIE_NAME => nil,
        SignIn::Constants::Auth::INFO_COOKIE_NAME => nil
      }
    end

    before do
      request.headers['Authorization'] = authorization
      request.cookies[SignIn::Constants::Auth::ACCESS_TOKEN_COOKIE_NAME] = access_token
      request.cookies[SignIn::Constants::Auth::REFRESH_TOKEN_COOKIE_NAME] = 'some-refresh-token'
      request.cookies[SignIn::Constants::Auth::ANTI_CSRF_COOKIE_NAME] = 'some-anti-csrf-token'
      request.cookies[SignIn::Constants::Auth::INFO_COOKIE_NAME] = 'some-info-token'
      allow(Rails.logger).to receive(:info)
    end

    shared_context 'error response' do
      let(:statsd_failure) { SignIn::Constants::Statsd::STATSD_SIS_LOGOUT_FAILURE }
      let(:expected_error_log) { '[SignInService] [V0::SignInController] logout error' }
      let(:expected_error_context) do
        { errors: expected_error_message, error_code:, client_id: client_id_value, post_logout_redirect_uri:,
          csp_type: nil, logout_type: nil }
      end
      let(:expected_error_status) { :bad_request }
      let(:expected_error_json) { { 'errors' => expected_error_message } }
      let(:error_code) { SignIn::Constants::ErrorCode::INVALID_REQUEST }

      it 'renders expected error' do
        expect(JSON.parse(subject.body)).to eq(expected_error_json)
      end

      it 'returns expected status' do
        expect(subject).to have_http_status(expected_error_status)
      end

      it 'triggers statsd increment for failed call' do
        expect { subject }.to trigger_statsd_increment(statsd_failure)
      end

      it 'logs the error message' do
        expect(Rails.logger).to receive(:info).with(expected_error_log, expected_error_context)
        subject
      end
    end

    shared_context 'authorization error response' do
      let(:statsd_failure) { SignIn::Constants::Statsd::STATSD_SIS_LOGOUT_FAILURE }
      let(:expected_error_log) { '[SignInService] [V0::SignInController] logout error' }
      let(:expected_error_context) do
        { errors: expected_error_message, error_code:, client_id: client_id_value, post_logout_redirect_uri:,
          csp_type: nil, logout_type: nil }
      end
      let(:error_code) { SignIn::Constants::ErrorCode::INVALID_REQUEST }

      it 'triggers statsd increment for failed call' do
        expect { subject }.to trigger_statsd_increment(statsd_failure)
      end

      it 'logs the error message' do
        expect(Rails.logger).to receive(:info).with(expected_error_log, expected_error_context)
        subject
      end

      it 'deletes the token cookies' do
        expect(subject.cookies).to eq(expected_cleared_cookies)
      end

      context 'when client configuration has not configured a logout redirect uri' do
        let(:logout_redirect_uri) { nil }
        let(:expected_error_status) { :ok }

        it 'returns expected status' do
          expect(subject).to have_http_status(expected_error_status)
        end
      end

      context 'when client configuration has configured a logout redirect uri' do
        let(:logout_redirect_uri) { 'https://some-logout-redirect-uri.com' }
        let(:expected_error_status) { :redirect }

        it 'returns expected status' do
          expect(subject).to have_http_status(expected_error_status)
        end

        it 'redirects to logout redirect url' do
          expect(subject).to redirect_to(logout_redirect_uri)
        end
      end
    end

    context 'when successfully authenticated' do
      let(:statsd_success) { SignIn::Constants::Statsd::STATSD_SIS_LOGOUT_SUCCESS }
      let(:logingov_uuid) { 'some-logingov-uuid' }
      let(:expected_log) { '[SignInService] [V0::SignInController] logout' }
      let(:expected_session_duration) { Time.zone.now.to_i - oauth_session.created_at.to_i }
      let(:expected_log_params) do
        {
          user_uuid: access_token_object.user_uuid,
          session_handle: access_token_object.session_handle,
          client_id: access_token_object.client_id,
          session_duration: expected_session_duration,
          post_logout_redirect_uri:,
          csp_type: nil,
          logout_type: nil
        }
      end
      let(:expected_status) { :redirect }

      before { Timecop.freeze }

      after { Timecop.return }

      it 'deletes the OAuthSession object matching the session_handle in the access token' do
        expect { subject }.to change {
          SignIn::OAuthSession.find_by(handle: access_token_object.session_handle)
        }.from(oauth_session).to(nil)
      end

      it 'deletes the token cookies' do
        expect(subject.cookies).to eq(expected_cleared_cookies)
      end

      it 'logs the logout call' do
        expect(Rails.logger).to receive(:info).with(expected_log, expected_log_params)
        subject
      end

      it 'triggers statsd increment for successful call' do
        expect { subject }.to trigger_statsd_increment(statsd_success)
      end

      context 'and a valid logout_type param is provided' do
        let(:logout_params) { { client_id: client_id_value, logout_type: 'user' } }

        it 'includes logout_type in the log' do
          expect(Rails.logger).to receive(:info).with(expected_log, hash_including(logout_type: 'user'))
          subject
        end
      end

      context 'and an unrecognized logout_type param is provided' do
        let(:logout_params) { { client_id: client_id_value, logout_type: 'invalid_type' } }

        it 'logs logout_type as nil' do
          expect(Rails.logger).to receive(:info).with(expected_log, hash_including(logout_type: nil))
          subject
        end
      end

      context 'and authenticated credential is Login.gov' do
        let(:user_verification) { create(:logingov_user_verification) }

        context 'and client configuration has not configured a logout redirect uri' do
          let(:logout_redirect_uri) { nil }
          let(:expected_status) { :ok }

          it 'returns ok status' do
            expect(subject).to have_http_status(expected_status)
          end
        end

        context 'and client configuration has configured a logout redirect uri' do
          let(:logingov_client_id) { IdentitySettings.logingov.client_id }
          let(:logout_redirect_uri) { 'https://some-logout-redirect-uri.com' }
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
          let(:expected_status) { :redirect }

          before do
            allow(SecureRandom).to receive(:hex).and_return(random_seed)
            allow_any_instance_of(SignIn::Logingov::Configuration).to receive(:ssl_key).and_return(ssl_key)
          end

          it 'returns redirect status' do
            expect(subject).to have_http_status(expected_status)
          end

          it 'redirects to login gov single sign out URL' do
            expect(subject).to redirect_to(expected_url)
          end
        end
      end

      context 'and authenticated credential is not Login.gov' do
        context 'and client configuration has not configured a logout redirect uri' do
          let(:logout_redirect_uri) { nil }
          let(:expected_status) { :ok }

          it 'returns ok status' do
            expect(subject).to have_http_status(expected_status)
          end
        end

        context 'and client configuration has configured a logout redirect uri' do
          let(:logout_redirect_uri) { 'https://some-logout-redirect-uri.com' }
          let(:expected_status) { :redirect }

          it 'returns redirect status' do
            expect(subject).to have_http_status(expected_status)
          end

          it 'redirects to the configured logout redirect uri' do
            expect(subject).to redirect_to(logout_redirect_uri)
          end
        end
      end

      context 'and a post_logout_redirect_uri param is provided' do
        let(:logout_params) { { client_id: client_id_value, post_logout_redirect_uri: } }
        let(:logout_redirect_uri) { 'https://login-stg.va.gov/login/signout' }

        context 'and its base matches the configured logout redirect uri' do
          let(:post_logout_redirect_uri) { 'https://login-stg.va.gov/login/signout?fromURI=some-from-uri' }

          it 'redirects to the post_logout_redirect_uri, preserving its query' do
            expect(subject).to redirect_to(post_logout_redirect_uri)
          end

          it 'logs the post_logout_redirect_uri' do
            expect(Rails.logger).to receive(:info)
              .with(expected_log, hash_including(client_id: client_id_value, post_logout_redirect_uri:))
            subject
          end
        end

        context 'and it is on a different host than the configured logout redirect uri' do
          let(:post_logout_redirect_uri) { 'https://malicious.example.com/login/signout' }

          it 'redirects to the configured logout redirect uri' do
            expect(subject).to redirect_to(logout_redirect_uri)
          end

          it 'still logs the requested post_logout_redirect_uri' do
            expect(Rails.logger).to receive(:info)
              .with(expected_log, hash_including(client_id: client_id_value, post_logout_redirect_uri:))
            subject
          end
        end
      end

      context 'and no session is found matching the access token session_handle' do
        let(:expected_error) { SignIn::Errors::SessionNotFoundError }
        let(:expected_error_message) { 'Session not found' }

        before { oauth_session.destroy! }

        it_behaves_like 'authorization error response'
      end

      context 'and the access token is expired' do
        let(:expiration_time) { Time.zone.now - SignIn::Constants::AccessToken::VALIDITY_LENGTH_SHORT_MINUTES }

        it 'deletes the OAuthSession object matching the session_handle in the access token' do
          expect { subject }.to change {
            SignIn::OAuthSession.find_by(handle: access_token_object.session_handle)
          }.from(oauth_session).to(nil)
        end

        it 'deletes the token cookies' do
          expect(subject.cookies).to eq(expected_cleared_cookies)
        end

        it 'triggers statsd increment for successful call' do
          expect { subject }.to trigger_statsd_increment(statsd_success)
        end

        it 'redirects to the configured logout redirect uri' do
          expect(subject).to redirect_to(logout_redirect_uri)
        end

        context 'and no session is found matching the access token session_handle' do
          let(:expected_error) { SignIn::Errors::SessionNotFoundError }
          let(:expected_error_message) { 'Session not found' }

          before { oauth_session.destroy! }

          it_behaves_like 'authorization error response'
        end
      end
    end

    context 'when not successfully authenticated' do
      context 'and the access token is invalid' do
        let(:access_token) { 'some-invalid-access-token' }
        let(:expected_error) { SignIn::Errors::LogoutAuthorizationError }
        let(:expected_error_message) { 'Unable to authorize access token' }

        it_behaves_like 'authorization error response'
      end
    end

    context 'when the client is the okta client' do
      let(:logout_redirect_uri) { 'https://login-stg.va.gov/login/signout' }
      let(:ssl_key) { OpenSSL::PKey::RSA.generate(2048) }
      let(:login_gov_logout_url) { "#{IdentitySettings.logingov.oauth_url}/openid_connect/logout" }

      before do
        allow(IdentitySettings.sign_in).to receive(:okta_client_id).and_return(client_config.client_id)
        allow_any_instance_of(SignIn::Logingov::Configuration).to receive(:ssl_key).and_return(ssl_key)
      end

      context 'and there is no authenticated session' do
        let(:access_token) { 'some-invalid-access-token' }

        context 'and csp_type is 200VLGN' do
          let(:logout_params) { { client_id: client_id_value, csp_type: '200VLGN' } }

          it 'redirects through the login.gov logout endpoint' do
            expect(subject).to have_http_status(:redirect)
            expect(subject.location).to start_with(login_gov_logout_url)
          end
        end

        context 'and csp_type is missing' do
          let(:logout_params) { { client_id: client_id_value } }

          it 'redirects through the login.gov logout endpoint' do
            expect(subject).to have_http_status(:redirect)
            expect(subject.location).to start_with(login_gov_logout_url)
          end
        end

        context 'and csp_type is not 200VLGN' do
          let(:logout_params) { { client_id: client_id_value, csp_type: '200VIDM' } }

          it 'redirects to the configured logout redirect uri without login.gov' do
            expect(subject).to redirect_to(logout_redirect_uri)
          end
        end
      end

      context 'and there is an authenticated session' do
        let(:logout_params) { { client_id: client_id_value, csp_type: '200VLGN' } }

        it 'ignores csp_type and lets the session credential decide' do
          expect(subject).to redirect_to(logout_redirect_uri)
        end
      end
    end

    context 'when a non-okta client passes csp_type 200VLGN with no authenticated session' do
      let(:access_token) { 'some-invalid-access-token' }
      let(:logout_params) { { client_id: client_id_value, csp_type: '200VLGN' } }

      it 'redirects to the configured logout redirect uri without login.gov' do
        expect(subject).to redirect_to(logout_redirect_uri)
      end
    end

    context 'when client_id is arbitrary' do
      let(:client_id_value) { 'some-client-id' }
      let(:expected_error_status) { :ok }
      let(:expected_error) { SignIn::Errors::MalformedParamsError }
      let(:expected_error_message) { 'Client id is not valid' }
      let(:logout_redirect_uri) { nil }

      it_behaves_like 'error response'
    end
  end
end
