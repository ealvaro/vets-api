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
    LOG_TAG   = 'job_tracker'

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
        orphans = 0
        alerts = []

        Sidekiq.redis do |conn|
          each_orphan(conn, alerts) do |jid, meta|
            orphans += 1 if recover_field(meta, conn, jid, log_only:, alerts:)
          end
        end

        post_slack_summary(alerts)
        orphans
      end

      private

      def each_orphan(conn, alerts)
        alive = alive_process_identities
        conn.hgetall(REDIS_KEY).each do |jid, json|
          meta = parse_meta_or_prune(conn, jid, json, alerts)
          next unless meta
          next if alive.include?(meta['process_identity'])

          yield jid, meta
        end
      end

      def parse_meta_or_prune(conn, jid, json, alerts)
        JSON.parse(json)
      rescue JSON::ParserError => e
        ClaimsApi::Logger.log(LOG_TAG,
                              level: :warn,
                              detail: 'Malformed tracker entry (JSON parse error)',
                              jid:,
                              error_class: e.class.name)
        alerts << orphan_alert_text(outcome: 'malformed_entry', jid:, meta: nil, error: e)
        conn.hdel(REDIS_KEY, jid)
        nil
      end

      def recover_field(meta, conn, jid, log_only:, alerts:)
        unless log_only
          begin
            meta['class'].constantize.perform_async(*meta['args'])
          rescue => e
            log_requeue_failure(jid, meta, e)
            alerts << orphan_alert_text(outcome: 'requeue_failed', jid:, meta:, error: e)
            return false # Don't delete field — job was not re-enqueued
          end
        end

        conn.hdel(REDIS_KEY, jid)
        log_recovery(jid, meta, log_only:)
        alerts << orphan_alert_text(outcome: log_only ? 'log_only' : 'requeued', jid:, meta:)
        true
      end

      def post_slack_summary(alerts)
        return if alerts.empty?

        webhook_url = Settings.claims_api.slack.webhook_url
        return if webhook_url.blank?

        noun = alerts.size == 1 ? 'orphaned job detected' : 'orphaned jobs detected'
        lines = alerts.map { |a| "• #{a}" }
        text = "[claims_api orphan recovery] #{alerts.size} #{noun}\n#{lines.join("\n")}"

        slack_client = SlackNotify::Client.new(
          webhook_url:,
          channel: '#api-benefits-claims-alerts',
          username: 'Claims API Orphaned Job Detector'
        )

        slack_client.notify(text)
      rescue SlackNotify::Error, Faraday::Error => e
        ClaimsApi::Logger.log(LOG_TAG,
                              level: :error,
                              detail: 'Slack alert failed',
                              error_class: e.class.name)
      end

      def orphan_alert_text(outcome:, jid:, meta:, error: nil)
        pid = meta ? meta['process_identity'] : 'unknown'
        klass = meta ? meta['class'] : 'unknown'
        args = (meta && meta['args']) || []
        arg_types = args.map { |a| a.class.name }.uniq
        types = arg_types.empty? ? 'nil' : arg_types.join(',')
        args_summary = "args=#{args.size}(#{types})"
        base = "[orphan #{outcome}] jid=#{jid} pid=#{pid} class=#{klass} #{args_summary}"
        error ? "#{base} error_class=#{error.class.name}" : base
      end

      # Processes whose heartbeat has expired (~60s TTL) are automatically
      # removed from ProcessSet by Redis. Only currently alive processes remain.
      def alive_process_identities
        Sidekiq::ProcessSet.new.to_set { |p| p['identity'] }
      end

      def log_requeue_failure(jid, meta, error)
        ClaimsApi::Logger.log(LOG_TAG,
                              level: :error,
                              detail: "Failed to recover orphaned job: #{error.message}",
                              jid:,
                              job_class: meta['class'])
      end

      def log_recovery(jid, meta, log_only:)
        ClaimsApi::Logger.log(LOG_TAG,
                              detail: log_only ? 'Orphaned job detected (log only)' : 'Recovered orphaned job',
                              jid:,
                              job_class: meta['class'],
                              process_identity: meta['process_identity'])
      end
    end
  end
end
