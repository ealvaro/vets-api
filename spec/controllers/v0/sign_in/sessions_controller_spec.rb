# frozen_string_literal: true

require 'rails_helper'

RSpec.describe V0::SignIn::SessionsController, type: :controller do
  describe 'GET index' do
    subject { get(:index) }

    context 'successfully returns user sessions' do
      let(:access_token) { SignIn::AccessTokenJwtEncoder.new(access_token: access_token_object).perform }
      let(:authorization) { "Bearer #{access_token}" }
      let(:user) { create(:user) }
      let(:user_verification) { user.user_verification }
      let(:user_account) { user.user_account }
      let(:user_uuid) { user.uuid }
      let(:oauth_session) { create(:oauth_session, user_account:) }
      let(:current_session_handle) { oauth_session.handle }
      let(:access_token_object) do
        create(:access_token, session_handle: current_session_handle, user_uuid:, client_id: oauth_session.client_id)
      end
      let(:oauth_session_count) { SignIn::OAuthSession.where(user_account:).count }
      let(:client_config) { SignIn::ClientConfig.find_by(client_id: oauth_session.client_id) }
      let(:client_id) { client_config.client_id }
      let(:statsd_success) { SignIn::Constants::Statsd::STATSD_SIS_SESSIONS_SUCCESS }
      let(:expected_log) { '[SignInService] [V0::SignInController] index' }
      let(:expected_log_values) { { user_uuid:, current_session_handle: } }
      let(:expected_status) { :ok }

      before do
        request.headers['Authorization'] = authorization
        allow(Rails.logger).to receive(:info)
      end

      context 'returns sessions associated with current user' do
        it 'and returns session values' do
          response = JSON.parse(subject.body)['data']
          expect(response.first['handle']).to eq(current_session_handle)
          expect(response.first['session_type']).to eq(client_config.authentication)
          expect(response.first['client_id']).to eq(client_id)
          expect(response.first['expiration']).to match(/\d{4}-\d{2}-\d{2}/)
          expect(response.first['current']).to be(true)
        end

        it 'and logs the sessions call' do
          expect(Rails.logger).to receive(:info).with(expected_log, expected_log_values)
          subject
        end

        it 'and returns ok status' do
          expect(subject).to have_http_status(expected_status)
        end

        it 'and returns expected body with handle' do
          expect(JSON.parse(subject.body)['data'].first).to have_key('handle')
        end

        it 'and returns expected body with session_type' do
          expect(JSON.parse(subject.body)['data'].first).to have_key('session_type')
        end

        it 'and returns expected body with client_id' do
          expect(JSON.parse(subject.body)['data'].first).to have_key('client_id')
        end

        it 'and returns expected body with expiration' do
          expect(JSON.parse(subject.body)['data'].first).to have_key('expiration')
        end

        it 'and returns expected body with current' do
          expect(JSON.parse(subject.body)['data'].first).to have_key('current')
        end

        it 'and triggers statsd increment for successful call' do
          expect { subject }.to trigger_statsd_increment(statsd_success)
        end
      end

      context 'returns multiple sessions for user account' do
        let!(:oauth_session2) { create(:oauth_session, user_account:) }
        let!(:oauth_session3) { create(:oauth_session, user_account:) }

        it 'returns all sessions for user account' do
          expect(JSON.parse(subject.body)['data'].count).to eq(oauth_session_count)
        end
      end
    end

    context 'when not authenticated' do
      it 'returns unauthorized' do
        expect(subject).to have_http_status(:unauthorized)
      end
    end
  end

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

      context 'and the target session has a companion record' do
        let!(:target_record) { create(:session_record, handle: target_session.handle) }

        it 'does not stamp the companion record' do
          expect { subject }.not_to change { target_record.reload.signed_out_at }
        end
      end
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

      context 'and companion session records exist' do
        let!(:target_record) { create(:session_record, handle: target_session.handle, user_account:) }
        let!(:current_record) { create(:session_record, handle: current_session.handle, user_account:) }

        it 'stamps signed_out_at on the target session record' do
          expect { subject }.to change { target_record.reload.signed_out_at }.from(nil)
        end

        it "does not stamp the caller's own session record" do
          expect { subject }.not_to change { current_record.reload.signed_out_at }
        end

        it 'does not delete the target session record' do
          subject
          expect(SignIn::SessionRecord.exists?(target_record.id)).to be(true)
        end

        it 'still returns ok status' do
          expect(subject).to have_http_status(expected_status)
        end
      end

      context 'and no companion session record exists' do
        it 'destroys the session and returns ok status' do
          expect { subject }.to change(SignIn::OAuthSession, :count).by(-1)
          expect(subject).to have_http_status(expected_status)
        end
      end
    end
  end
end
