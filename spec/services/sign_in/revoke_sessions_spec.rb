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
    end

    context 'when the given session is the only session for the account' do
      let!(:other_session) { nil }

      it 'does not revoke any sessions' do
        expect { subject }.not_to change(SignIn::OAuthSession, :count)
      end
    end
  end
end
