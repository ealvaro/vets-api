# frozen_string_literal: true

module SignIn
  class DeleteExpiredSessionsJob
    include Sidekiq::Job

    def perform
      sessions = expired_oauth_sessions
      handles = sessions.pluck(:handle)
      sessions.destroy_all
      SessionRecord.sign_out(handles)
    end

    private

    def time_in_past
      ...Time.zone.now
    end

    def expired_oauth_sessions
      OAuthSession.where(refresh_expiration: time_in_past)
    end
  end
end
