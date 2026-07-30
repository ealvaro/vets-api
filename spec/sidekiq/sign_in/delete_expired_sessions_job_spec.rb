# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SignIn::DeleteExpiredSessionsJob do
  let!(:expired_oauth_session) { create(:oauth_session, refresh_expiration: 3.days.ago) }
  let!(:active_oauth_session) { create(:oauth_session, refresh_expiration: 3.days.from_now) }

  describe '#perform' do
    let(:job) { SignIn::DeleteExpiredSessionsJob.new }

    it 'deletes expired oauth sessions' do
      expect { job.perform }.to change(SignIn::OAuthSession, :count).by(-1)
    end

    it 'does not delete active oauth sessions' do
      expect { job.perform }.not_to change(active_oauth_session, :reload)
    end

    context 'when session records exist for the sessions' do
      let!(:expired_session_record) do
        create(:session_record, handle: expired_oauth_session.handle,
                                user_account: expired_oauth_session.user_account,
                                client_id: expired_oauth_session.client_id)
      end
      let!(:active_session_record) do
        create(:session_record, handle: active_oauth_session.handle,
                                user_account: active_oauth_session.user_account,
                                client_id: active_oauth_session.client_id)
      end

      it 'stamps signed_out_at on session records for expired sessions' do
        expect { job.perform }.to change { expired_session_record.reload.signed_out_at }.from(nil)
      end

      it 'does not stamp signed_out_at on session records for active sessions' do
        expect { job.perform }.not_to change { active_session_record.reload.signed_out_at }.from(nil)
      end
    end
  end
end
