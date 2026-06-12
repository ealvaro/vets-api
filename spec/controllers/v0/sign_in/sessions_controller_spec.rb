# frozen_string_literal: true

require 'rails_helper'

RSpec.describe V0::SignIn::SessionsController, type: :controller do
  describe 'DELETE destroy' do
    subject { delete(:destroy, params: { handle: }) }

    let(:handle) { target_session.handle }
    let(:access_token) { SignIn::AccessTokenJwtEncoder.new(access_token: access_token_object).perform }
    let(:user) { create(:user, :loa3) }
    let(:user_account) { user.user_account }
    let(:current_session) { create(:oauth_session, user_account:) }
    let(:access_token_object) do
      create(:access_token, session_handle: current_session.handle, user_uuid: user.uuid)
    end

    before do
      request.headers['Authorization'] = "Bearer #{access_token}"
      allow(Rails.logger).to receive(:info)
    end

    shared_context 'error response' do
      let(:statsd_failure) { SignIn::Constants::Statsd::STATSD_SIS_DESTROY_SESSION_FAILURE }
      let(:expected_error_json) { { 'errors' => expected_error_message } }
      let(:expected_error_log) { '[SignInService] [V0::SignInController] destroy error' }
      let(:expected_error_context) { { errors: expected_error_message, error_code: } }
      let(:expected_error_status) { :unauthorized }
      let(:error_code) { SignIn::Constants::ErrorCode::INVALID_REQUEST }

      it 'renders expected error' do
        expect(JSON.parse(subject.body)).to eq(expected_error_json)
      end

      it 'returns expected status' do
        expect(subject).to have_http_status(expected_error_status)
      end

      it 'logs the failed destroy call' do
        expect(Rails.logger).to receive(:info).with(expected_error_log, expected_error_context)
        subject
      end

      it 'triggers statsd increment for failed call' do
        expect { subject }.to trigger_statsd_increment(statsd_failure)
      end

      it 'does not destroy a session' do
        expect { subject }.not_to change(SignIn::OAuthSession, :count)
      end
    end

    context 'and no session matches the given handle' do
      let(:handle) { 'some-nonexistent-handle' }
      let(:expected_error_message) { 'Requested session not found' }

      before { current_session }

      it_behaves_like 'error response'
    end

    context 'and the session is owned by a different user account' do
      let(:other_user) { create(:user, :loa3) }
      let(:target_session) { create(:oauth_session, user_account: other_user.user_account) }
      let(:expected_error_message) { 'Requested session not found' }

      before do
        current_session
        target_session
      end

      it_behaves_like 'error response'
    end

    context 'and the caller owns the target session' do
      let(:target_session) { create(:oauth_session, user_account:) }
      let(:statsd_success) { SignIn::Constants::Statsd::STATSD_SIS_DESTROY_SESSION_SUCCESS }
      let(:expected_log) { '[SignInService] [V0::SignInController] destroy' }
      let(:expected_log_params) do
        {
          user_uuid: access_token_object.user_uuid,
          session_handle: target_session.handle,
          client_id: target_session.client_id
        }
      end
      let(:expected_status) { :ok }

      before do
        current_session
        target_session
      end

      it 'destroys the target session' do
        expect { subject }.to change { SignIn::OAuthSession.find_by(handle: target_session.handle) }
          .from(target_session).to(nil)
      end

      it "does not destroy the caller's own session" do
        subject
        expect(SignIn::OAuthSession.find_by(handle: current_session.handle)).to be_present
      end

      it 'returns ok status' do
        expect(subject).to have_http_status(expected_status)
      end

      it 'logs the destroy call' do
        expect(Rails.logger).to receive(:info).with(expected_log, expected_log_params)
        subject
      end

      it 'triggers statsd increment for successful call' do
        expect { subject }.to trigger_statsd_increment(statsd_success)
      end
    end
  end
end
