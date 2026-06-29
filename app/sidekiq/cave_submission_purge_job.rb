# frozen_string_literal: true

# Purges CaveSubmission records once they pass their delete_date.
#
# A CaveSubmission holds extracted document PII (the OCR response and the user-correction
# change log) only long enough to generate the 21-4138 and forward corrections to CAVE.
# delete_date is set at creation (CaveSubmission::RETENTION_DAYS); this job removes expired rows.
#
# Schedule: daily (see lib/periodic_jobs.rb).
class CaveSubmissionPurgeJob
  include Sidekiq::Job

  sidekiq_options unique_for: 30.minutes, retry: false

  STATS_KEY = 'api.cave_submission.data_purge'
  BATCH_SIZE = 1000

  def perform
    StatsD.increment("#{STATS_KEY}.started")

    total = 0
    loop do
      # Only rows whose delete_date has passed are purged. Rows with a NULL
      # delete_date (created before retention shipped) are intentionally left
      # for an explicit backfill rather than auto-deleted here.
      batch_ids = CaveSubmission.where(delete_date: ..Time.current).limit(BATCH_SIZE).pluck(:id)
      break if batch_ids.empty?

      emit_pii_event('pii.deleting', batch_ids, scheduled_for_deletion_at: Time.current)
      total += CaveSubmission.where(id: batch_ids).delete_all
      emit_pii_event('pii.deleted', batch_ids, deleted_at: Time.current)
      break if batch_ids.length < BATCH_SIZE
    end

    StatsD.gauge("#{STATS_KEY}.purged", total)
    StatsD.increment("#{STATS_KEY}.completed")
    Rails.logger.info('CaveSubmissionPurgeJob completed', purged: total)
  rescue => e
    StatsD.increment("#{STATS_KEY}.failed")
    Rails.logger.error('CaveSubmissionPurgeJob failed', error: e.message, backtrace: e.backtrace&.first(5))
    raise
  end

  private

  # Emits an auditable PII-deletion notification. The payload carries only record identifiers
  # and timestamps (never cave_response / change_log values), mirroring ScannedUploadPurgeJob.
  def emit_pii_event(event, ids, **timestamps)
    ActiveSupport::Notifications.instrument(
      event,
      { record_type: 'CaveSubmission', cave_submission_ids: ids, count: ids.size, **timestamps }
    )
  end
end
