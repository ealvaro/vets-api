# frozen_string_literal: true

module SignIn
  class SessionRecordCleanUpJob
    include Sidekiq::Job

    sidekiq_options retry: 3

    RETENTION_PERIOD = 30.days
    BATCH_SIZE = 10_000

    def perform
      total = 0

      SessionRecord.where(signed_out_at: ...RETENTION_PERIOD.ago)
                   .in_batches(of: BATCH_SIZE) { |batch| total += batch.delete_all }

      logger.info('signed out session records purged', { deleted_count: total })
      total
    end

    private

    def logger
      @logger ||= SignIn::Logger.new(prefix: self.class.name)
    end
  end
end
