# frozen_string_literal: true

require 'socket'
require 'claims_api/job_tracker'

module ClaimsApi
  ##
  # Sidekiq server middleware that tracks in-flight ClaimsApi jobs.
  #
  # Writes a Redis hash field when a job starts, deletes it on completion or failure.
  # Only a process crash leaves a field behind. That's what makes orphan
  # detection work. See ClaimsApi::JobTracker for the recovery side.
  #
  # Controlled by Flipper :claims_api_job_tracker flag.
  # Scoped to ClaimsApi jobs only. Other modules pass through untouched.
  #
  class JobTrackerMiddleware
    def call(worker, job, _queue)
      return yield unless worker.class.name.start_with?('ClaimsApi')
      return yield unless Flipper.enabled?(:claims_api_job_tracker)

      tracked = track_job(worker, job)

      begin
        yield
      ensure
        # ensure runs after both success and failure, then lets the
        # original exception (if any) propagate with its full backtrace.
        # Wrapped in rescue so a Redis error here doesn't mask the original exception.
        begin
          JobTracker.remove(job['jid']) if tracked
        rescue => e
          ClaimsApi::Logger.log('job_tracker_middleware',
                                level: :warn,
                                message: "failed to remove tracker key #{job['jid']}: #{e.message}")
        end
      end
    end

    private

    def track_job(worker, job)
      JobTracker.track(
        jid: job['jid'],
        job_class: worker.class.name,
        args: job['args'],
        process_identity:
      )
      true
    rescue => e
      ClaimsApi::Logger.log('job_tracker_middleware',
                            level: :warn,
                            message: "failed to track job #{job['jid']}: #{e.message}")
      false
    end

    # Sidekiq's own identity (hostname:pid:random_hex) — matches exactly
    # what ProcessSet returns, so tracker keys align during orphan recovery.
    # Fallback handles non-server contexts (rails console, tests) where
    # the Sidekiq Launcher hasn't set [:identity] yet.
    # Memoized because identity never changes during a process's lifetime.
    def process_identity
      @process_identity ||=
        Sidekiq.default_configuration[:identity] || "#{Socket.gethostname}:#{::Process.pid}"
    end
  end
end
