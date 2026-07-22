# frozen_string_literal: true

require 'claims_api/job_tracker'

module ClaimsApi
  ##
  # Runs orphan recovery on Sidekiq startup (via perform_in delay).
  #
  # Scheduled 65s after boot to allow dead process heartbeats to expire
  # from Redis (~60s TTL). Scans for tracker fields from dead processes
  # and optionally re-enqueues orphaned jobs (default is log-only).
  #
  # Controlled by Flipper :claims_api_job_tracker flag.
  #
  class JobTrackerRecoveryJob
    include Sidekiq::Job

    sidekiq_options retry: false

    def perform
      return unless Flipper.enabled?(:claims_api_job_tracker)

      # On vets-api (Pro/Enterprise), super_fetch! already recovers orphans.
      # Default log_only: true just detects and logs — no re-enqueue.
      orphans = ClaimsApi::JobTracker.recover_orphans!
      ClaimsApi::Logger.log('job_tracker_recovery', message: "#{orphans} orphaned jobs found") if orphans.positive?
    end
  end
end
