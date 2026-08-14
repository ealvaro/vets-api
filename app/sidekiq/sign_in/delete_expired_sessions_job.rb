# frozen_string_literal: true

module SignIn
  class DeleteExpiredSessionsJob
    include Sidekiq::Job

    BATCH_SIZE = 1_000

    def perform
      expired_oauth_sessions.in_batches(of: BATCH_SIZE) do |batch|
        handles = batch.pluck(:handle)
        batch.delete_all
        SessionRecord.sign_out(handles)
      end
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
