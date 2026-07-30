# frozen_string_literal: true

module SignIn
  class RevokeSessionsForUser
    attr_reader :user_account, :sessions

    def initialize(user_account:)
      @user_account = user_account
    end

    def perform
      delete_sessions!
    end

    private

    def delete_sessions!
      sessions = OAuthSession.where(user_account:)
      handles = sessions.pluck(:handle)
      sessions.destroy_all
      SessionRecord.sign_out(handles)
    end
  end
end
