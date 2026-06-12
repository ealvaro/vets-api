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
      OAuthSession.where(user_account: session.user_account).where.not(handle: session.handle).destroy_all
    end
  end
end
