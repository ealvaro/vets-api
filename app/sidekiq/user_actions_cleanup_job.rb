# frozen_string_literal: true

class UserActionsCleanupJob
  include Sidekiq::Job

  sidekiq_options unique_for: 30.minutes, retry: false

  EXPIRATION_TIME = 1.year

  def perform
    UserAction.where(created_at: ...EXPIRATION_TIME.ago).in_batches(of: 10_000).delete_all
  end
end
