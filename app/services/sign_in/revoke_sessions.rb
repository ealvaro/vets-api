# frozen_string_literal: true

module SignIn
  class RevokeSessions
    attr_reader :session

    def initialize(session:)
      @session = session
    end

    def perform
      delete_sessions!
    end

    private

    def delete_sessions!
      sessions = OAuthSession.where(user_account: session.user_account).where.not(handle: session.handle)
      handles = sessions.pluck(:handle)
      sessions.destroy_all
      SessionRecord.sign_out(handles)
    end
  end
end
