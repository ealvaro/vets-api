# frozen_string_literal: true

require 'sidekiq'

module DecisionReviews
  class DeleteSecondaryAppealFormsJob
    include Sidekiq::Job

    # No need to retry since the schedule will run this periodically
    sidekiq_options retry: false

    STATSD_KEY_PREFIX = 'worker.decision_review.delete_secondary_appeal_forms'

    BATCH_SIZE = 1000

    def perform
      return unless enabled?

      total_deleted = 0
      SecondaryAppealForm.where(delete_date: ..DateTime.now).in_batches(of: BATCH_SIZE) do |batch|
        total_deleted += batch.destroy_all.size
      end

      StatsD.increment("#{STATSD_KEY_PREFIX}.count", total_deleted)

      Rails.logger.info('DecisionReviews::DeleteSecondaryAppealFormsJob completed successfully',
                        secondary_forms_deleted: total_deleted)

      nil
    rescue => e
      StatsD.increment("#{STATSD_KEY_PREFIX}.error")
      Rails.logger.error('DecisionReviews::DeleteSecondaryAppealFormsJob perform exception', e.message)
    end

    private

    def enabled?
      Flipper.enabled? :decision_review_delete_secondary_appeal_forms_enabled
    end
  end
end
