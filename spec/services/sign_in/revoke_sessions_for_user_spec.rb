# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SignIn::RevokeSessionsForUser do
  describe '#perform' do
    subject { SignIn::RevokeSessionsForUser.new(user_account:).perform }

    let(:user_account) { create(:user_account) }
    let!(:oauth_session_1) { create(:oauth_session, user_account:) }
    let!(:oauth_session_2) { create(:oauth_session, user_account:) }
    let(:oauth_session_count) { SignIn::OAuthSession.where(user_account:).count }

    it 'deletes all sessions associated with given user account' do
      expect { subject }.to change(SignIn::OAuthSession, :count).from(oauth_session_count).to(0)
    end

    context 'when companion session records exist' do
      let!(:session_record_1) { create(:session_record, handle: oauth_session_1.handle, user_account:) }
      let!(:session_record_2) { create(:session_record, handle: oauth_session_2.handle, user_account:) }

      it 'stamps signed_out_at on every session record for the account' do
        subject

        expect(session_record_1.reload.signed_out_at).to be_present
        expect(session_record_2.reload.signed_out_at).to be_present
      end

      it 'does not delete the session records' do
        expect { subject }.not_to change(SignIn::SessionRecord, :count)
      end

      it 'stamps them in a single query' do
        expect(SignIn::SessionRecord).to receive(:sign_out).once.and_call_original
        subject
      end

      context 'and a record is already signed out' do
        let(:original_timestamp) { 3.days.ago.round }
        let!(:session_record_1) do
          create(:session_record, handle: oauth_session_1.handle, user_account:, signed_out_at: original_timestamp)
        end

        it 'does not overwrite the original timestamp' do
          expect { subject }.not_to change { session_record_1.reload.signed_out_at }
        end

        it 'still stamps the active record' do
          expect { subject }.to change { session_record_2.reload.signed_out_at }.from(nil)
        end
      end
    end

    context 'when another user account has sessions' do
      let(:other_account) { create(:user_account) }
      let!(:unrelated_session) { create(:oauth_session, user_account: other_account) }
      let!(:unrelated_record) do
        create(:session_record, handle: unrelated_session.handle, user_account: other_account)
      end

      it 'does not delete the unrelated session' do
        subject
        expect(SignIn::OAuthSession.find_by(handle: unrelated_session.handle)).to be_present
      end

      it 'does not stamp the unrelated session record' do
        expect { subject }.not_to change { unrelated_record.reload.signed_out_at }
      end
    end

    context 'when no companion session records exist' do
      it 'revokes without raising' do
        expect { subject }.not_to raise_error
      end
    end
  end
end
