# frozen_string_literal: true

require 'rails_helper'

RSpec.describe V0::SignIn::OktaLogoutController, type: :controller do
  describe 'GET logout' do
    subject { get(:logout) }

    let!(:client_config) { create(:client_config, logout_redirect_uri:) }
    let(:okta_client_id) { client_config.client_id }
    let(:logout_redirect_uri) { 'some-logout-redirect-uri' }
    let(:access_token) { SignIn::AccessTokenJwtEncoder.new(access_token: access_token_object).perform }
    let(:authorization) { "Bearer #{access_token}" }
    let(:created_at) { 1.day.ago }
    let(:oauth_session) { create(:oauth_session, user_verification:, created_at:) }
    let(:user_verification) { create(:user_verification) }
    let(:access_token_object) do
      create(:access_token, session_handle: oauth_session.handle, client_id: client_config.client_id, expiration_time:)
    end
    let(:expiration_time) { Time.zone.now + SignIn::Constants::AccessToken::VALIDITY_LENGTH_SHORT_MINUTES }

    before do
      allow(IdentitySettings.sign_in).to receive(:okta_client_id).and_return(okta_client_id)
      request.headers['Authorization'] = authorization
      allow(Rails.logger).to receive(:info)
    end

    it 'resolves the client_id from the okta_client_id setting' do
      expect(IdentitySettings.sign_in).to receive(:okta_client_id).and_return(okta_client_id)
      subject
    end

    context 'when successfully authenticated' do
      let(:statsd_success) { SignIn::Constants::Statsd::STATSD_SIS_OKTA_LOGOUT_SUCCESS }
      let(:expected_log) { '[SignInService] [V0::SignInController] okta logout' }
      let(:expected_log_params) do
        {
          user_uuid: access_token_object.user_uuid,
          session_handle: access_token_object.session_handle,
          client_id: access_token_object.client_id,
          session_duration: Time.zone.now.to_i - oauth_session.created_at.to_i,
          post_logout_redirect_uri: nil,
          csp_type: nil
        }
      end

      before { Timecop.freeze }

      after { Timecop.return }

      it 'deletes the OAuthSession object matching the session_handle in the access token' do
        expect { subject }.to change {
          SignIn::OAuthSession.find_by(handle: access_token_object.session_handle)
        }.from(oauth_session).to(nil)
      end

      it 'logs the okta logout call' do
        expect(Rails.logger).to receive(:info).with(expected_log, expected_log_params)
        subject
      end

      it 'triggers statsd increment for successful call' do
        expect { subject }.to trigger_statsd_increment(statsd_success)
      end

      context 'and the client configuration has a configured logout redirect uri' do
        let(:logout_redirect_uri) { 'some-logout-redirect-uri' }

        it 'redirects to the configured logout redirect uri' do
          expect(subject).to redirect_to(logout_redirect_uri)
        end
      end

      context 'and the client configuration has not configured a logout redirect uri' do
        let(:logout_redirect_uri) { nil }

        it 'returns ok status' do
          expect(subject).to have_http_status(:ok)
        end
      end

      context 'and a post_logout_redirect_uri param matching the configured base is provided' do
        subject { get(:logout, params: { post_logout_redirect_uri: }) }

        let(:logout_redirect_uri) { 'https://login-stg.va.gov/login/signout' }
        let(:post_logout_redirect_uri) { 'https://login-stg.va.gov/login/signout?fromURI=some-from-uri' }

        it 'redirects to the post_logout_redirect_uri, preserving its query' do
          expect(subject).to redirect_to(post_logout_redirect_uri)
        end
      end
    end

    context 'when the okta client configuration cannot be found' do
      let(:okta_client_id) { 'some-unknown-client-id' }
      let(:statsd_failure) { SignIn::Constants::Statsd::STATSD_SIS_OKTA_LOGOUT_FAILURE }

      it 'triggers statsd increment for failed call' do
        expect { subject }.to trigger_statsd_increment(statsd_failure)
      end

      it 'returns bad request status' do
        expect(subject).to have_http_status(:bad_request)
      end
    end
  end
end
