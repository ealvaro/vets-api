# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SignIn::RevokeSessions do
  describe '#perform' do
    subject { SignIn::RevokeSessions.new(session:).perform }

    let(:user_account) { create(:user_account) }
    let!(:session) { create(:oauth_session, user_account:) }
    let!(:other_session) { create(:oauth_session, user_account:) }

    it 'revokes all sessions for the account except the given session' do
      expect { subject }.to change(SignIn::OAuthSession, :count).from(2).to(1)
    end

    it 'preserves the given session' do
      subject
      expect(SignIn::OAuthSession.find_by(handle: session.handle)).to be_present
    end

    it 'deletes the other sessions' do
      subject
      expect(SignIn::OAuthSession.find_by(handle: other_session.handle)).to be_nil
    end

    context 'when sessions exist for a different user account' do
      let(:other_account) { create(:user_account) }
      let!(:unrelated_session) { create(:oauth_session, user_account: other_account) }

      it 'does not revoke sessions belonging to other accounts' do
        subject
        expect(SignIn::OAuthSession.find_by(handle: unrelated_session.handle)).to be_present
      end

      context 'and the unrelated session has a companion record' do
        let!(:unrelated_record) { create(:session_record, handle: unrelated_session.handle) }

        it 'does not stamp the unrelated session record' do
          expect { subject }.not_to change { unrelated_record.reload.signed_out_at }
        end
      end
    end

    context 'when the given session is the only session for the account' do
      let!(:other_session) { nil }

      it 'does not revoke any sessions' do
        expect { subject }.not_to change(SignIn::OAuthSession, :count)
      end
    end

    context 'when companion session records exist' do
      let!(:session_record) { create(:session_record, handle: session.handle) }
      let!(:other_record) { create(:session_record, handle: other_session.handle) }

      it 'stamps signed_out_at on the revoked session record' do
        expect { subject }.to change { other_record.reload.signed_out_at }.from(nil)
      end

      it 'does not stamp the current session record' do
        expect { subject }.not_to change { session_record.reload.signed_out_at }
      end

      it 'does not delete the revoked session record' do
        subject
        expect(SignIn::SessionRecord.exists?(other_record.id)).to be(true)
      end

      context 'and several sessions are revoked at once' do
        let!(:third_session) { create(:oauth_session, user_account:) }
        let!(:third_record) { create(:session_record, handle: third_session.handle) }

        it 'stamps every revoked session record' do
          subject

          expect(other_record.reload.signed_out_at).to be_present
          expect(third_record.reload.signed_out_at).to be_present
        end

        it 'stamps them in a single query' do
          expect(SignIn::SessionRecord).to receive(:sign_out).once.and_call_original
          subject
        end
      end
    end

    context 'when no companion session records exist' do
      it 'revokes without raising' do
        expect { subject }.not_to raise_error
      end
    end
  end
end
