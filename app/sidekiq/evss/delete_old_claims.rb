# frozen_string_literal: true

module EVSS
  class DeleteOldClaims
    include Sidekiq::Job

    sidekiq_options queue: 'low'

    BATCH_SIZE = 1000

    def perform
      deleted_count = 0
      EVSSClaim.where('updated_at < ?', 1.day.ago).in_batches(of: BATCH_SIZE) do |batch|
        deleted_count += batch.delete_all
      end
      logger.info("Deleted #{deleted_count} old EVSS claims")
    end
  end
end
