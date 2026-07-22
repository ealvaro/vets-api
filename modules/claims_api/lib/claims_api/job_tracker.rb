# frozen_string_literal: true

require 'sidekiq/api'

module ClaimsApi
  ##
  # Tracks in-flight Sidekiq jobs in Redis for crash recovery.
  #
  # All tracked jobs are fields in a single Redis hash (REDIS_KEY).
  # Each field is keyed by jid, value is JSON metadata.
  # HSET/HDEL are O(1) per field. HGETALL scales with running job count,
  # not the entire Redis keyspace — no SCAN needed.
  #
  # When a job starts, a field is written. When it finishes, the field is deleted.
  # If a process crashes mid-job, the field stays behind (an orphan).
  #
  # recover_orphans! waits for heartbeat TTL expiry (~60s) then checks
  # ProcessSet for alive processes. Any field whose process_identity is
  # not in ProcessSet is orphaned. This mirrors Sidekiq Pro's super_fetch
  # approach, which also waits for heartbeat expiry before recovering.
  #
  # Alternative: check beat timestamps directly (process['beat']) for faster
  # detection (updates every ~5s vs ~65s). Traded off to match super_fetch
  # behavior and avoid false positives from clock skew.
  #
  # Uses Sidekiq's own Redis connection, so no additional dependencies.
  #
  class JobTracker
    REDIS_KEY = 'claims_api:running_jobs'

    class << self
      def track(jid:, job_class:, args:, process_identity:)
        data = {
          jid:,
          class: job_class,
          args:,
          process_identity:,
          started_at: Time.current.to_f
        }.to_json

        Sidekiq.redis { |conn| conn.hset(REDIS_KEY, jid, data) }
      end

      def remove(jid)
        Sidekiq.redis { |conn| conn.hdel(REDIS_KEY, jid) }
      end

      def recover_orphans!(log_only: true)
        alive = alive_process_identities
        orphans = 0

        Sidekiq.redis do |conn|
          conn.hgetall(REDIS_KEY).each do |jid, json|
            meta = begin
              JSON.parse(json)
            rescue JSON::ParserError => e
              ClaimsApi::Logger.log('job_tracker',
                                    level: :warn,
                                    detail: "Malformed tracker entry: #{e.message}",
                                    jid:)
              conn.hdel(REDIS_KEY, jid)
              next
            end
            next if alive.include?(meta['process_identity'])

            orphans += 1 if recover_field(meta, conn, jid, log_only:)
          end
        end

        # TODO: Add Slack alert for when orphans are detected:
        # - what jid/pid specifically,
        # - what class and params (job signature),
        # - and what we did with it:
        # logged only, requeue (new jid), failed to requeue, etc.
        # This would give human visibility into what jobs are being orphaned and how often.

        orphans
      end

      private

      def recover_field(meta, conn, jid, log_only:)
        unless log_only
          begin
            meta['class'].constantize.perform_async(*meta['args'])
          rescue => e
            ClaimsApi::Logger.log('job_tracker',
                                  level: :error,
                                  detail: "Failed to recover orphaned job: #{e.message}",
                                  jid:,
                                  job_class: meta['class'])
            return false # Don't delete field — job was not re-enqueued
          end
        end

        conn.hdel(REDIS_KEY, jid)

        ClaimsApi::Logger.log('job_tracker',
                              detail: log_only ? 'Orphaned job detected (log only)' : 'Recovered orphaned job',
                              jid:,
                              job_class: meta['class'],
                              process_identity: meta['process_identity'])
        true
      end

      # Processes whose heartbeat has expired (~60s TTL) are automatically
      # removed from ProcessSet by Redis. Only currently alive processes remain.
      def alive_process_identities
        Sidekiq::ProcessSet.new.to_set { |p| p['identity'] }
      end
    end
  end
end
