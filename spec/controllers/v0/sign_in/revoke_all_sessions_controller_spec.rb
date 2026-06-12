# frozen_string_literal: true

require 'rails_helper'

RSpec.describe V0::SignIn::RevokeAllSessionsController, type: :controller do
  describe 'POST revoke_all_sessions' do
    subject { post(:revoke_all_sessions) }

    shared_context 'error response' do
      let(:statsd_failure) { SignIn::Constants::Statsd::STATSD_SIS_REVOKE_ALL_SESSIONS_FAILURE }
      let(:expected_error_json) { { 'errors' => expected_error_message } }
      let(:expected_error_status) { :unauthorized }
      let(:expected_error_log) { '[SignInService] [V0::SignInController] revoke all sessions error' }
      let(:expected_error_context) { { errors: expected_error_message, error_code: } }
      let(:error_code) { SignIn::Constants::ErrorCode::INVALID_REQUEST }

      before do
        allow(Rails.logger).to receive(:info)
      end

      it 'renders expected error' do
        expect(JSON.parse(subject.body)).to eq(expected_error_json)
      end

      it 'returns expected status' do
        expect(subject).to have_http_status(expected_error_status)
      end

      it 'logs the failed revoke all sessions call' do
        expect(Rails.logger).to receive(:info).with(expected_error_log, expected_error_context)
        subject
      end

      it 'triggers statsd increment for failed call' do
        expect { subject }.to trigger_statsd_increment(statsd_failure)
      end
    end

    context 'when successfully authenticated' do
      let(:access_token) { SignIn::AccessTokenJwtEncoder.new(access_token: access_token_object).perform }
      let(:authorization) { "Bearer #{access_token}" }
      let(:user) { create(:user, :loa3) }
      let(:user_verification) { user.user_verification }
      let(:user_account) { user.user_account }
      let(:user_uuid) { user.uuid }
      let(:oauth_session) { create(:oauth_session, user_account:) }
      let(:access_token_object) do
        create(:access_token, session_handle: oauth_session.handle, user_uuid:)
      end
      let(:statsd_success) { SignIn::Constants::Statsd::STATSD_SIS_REVOKE_ALL_SESSIONS_SUCCESS }
      let(:expected_log) { '[SignInService] [V0::SignInController] revoke all sessions' }
      let(:expected_log_params) { access_token_object.to_s }
      let(:expected_status) { :ok }

      before do
        request.headers['Authorization'] = authorization
      end

      context 'and no session matches the access token session handle' do
        let(:expected_error) { SignIn::Errors::SessionNotFoundError }
        let(:expected_error_message) { 'Session not found' }

        before do
          oauth_session.destroy!
        end

        it_behaves_like 'error response'
      end

      context 'and some arbitrary Sign in Error is raised' do
        let(:expected_error) { SignIn::Errors::StandardError }
        let(:expected_error_message) { expected_error.to_s }

        before do
          allow(SignIn::RevokeSessions).to receive(:new).and_raise(expected_error.new(message: expected_error))
        end

        it_behaves_like 'error response'
      end

      context 'and the user has other sessions' do
        let!(:other_session) { create(:oauth_session, user_account:) }

        before { oauth_session }

        it 'revokes all sessions except the current session' do
          expect { subject }.to change(SignIn::OAuthSession, :count).from(2).to(1)
        end

        it 'preserves the current session' do
          subject
          expect(SignIn::OAuthSession.find_by(handle: oauth_session.handle)).to be_present
        end

        it 'returns ok status' do
          expect(subject).to have_http_status(expected_status)
        end

        it 'logs the revoke all sessions call' do
          expect(Rails.logger).to receive(:info).with(expected_log, expected_log_params)
          subject
        end

        it 'triggers statsd increment for successful call' do
          expect { subject }.to trigger_statsd_increment(statsd_success)
        end
      end
    end
  end
end
