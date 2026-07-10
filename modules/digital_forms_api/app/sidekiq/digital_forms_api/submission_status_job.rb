# frozen_string_literal: true

require 'digital_forms_api/service/submissions'

module DigitalFormsApi
  # Periodic poller (every 2h, registered in lib/periodic_jobs.rb) that reconciles pending FDF
  # SubmissionAttempts against the BIP Forms API. Per attempt it calls retrieve and infers status
  # — v1, intentionally narrow: documentId present -> accepted, 404 -> failed, else stays pending.
  # It only calls the attempt's bang setters; the base ::SubmissionAttempt callback cascades the
  # new status into the parent Submission#latest_status (the poller never writes it directly).
  # Per-record failures are isolated so one bad row can't abort the run; retry:false + a top-level
  # rescue means a whole-run hiccup is logged, not re-raised (recovery is the next tick).
  class SubmissionStatusJob
    include Sidekiq::Job

    sidekiq_options retry: false

    # StatsD namespace (.poll increment, .queue_depth gauge, .duration_ms measure).
    STATSD_PREFIX = 'api.digital_forms_api.submission_status_job'
    # Per-attempt outcome counter, tagged form_id + outcome (+ http_status when relevant).
    POLL_METRIC = "#{STATSD_PREFIX}.poll".freeze
    # Max attempts polled per run; the queue_depth gauge surfaces backlog beyond this cap.
    MAX_POLL_BATCH = 500
    # Kill switch (config/features.yml); the job no-ops unless enabled.
    FLIPPER_FLAG = :digital_forms_api_submission_status_job_enabled

    # Gauge the backlog, poll up to MAX_POLL_BATCH pending attempts (oldest first), measure duration.
    def perform
      return unless Flipper.enabled?(FLIPPER_FLAG)

      started_ms = monotonic_ms
      StatsD.gauge("#{STATSD_PREFIX}.queue_depth", DigitalFormsApi::SubmissionAttempt.pending_for_polling.count)
      pending_batch.each { |attempt| poll(attempt) }
    rescue => e # a whole-run failure is logged, not re-raised (avoids Sidekiq exhaustion alerts)
      Rails.logger.error('DigitalFormsApi::SubmissionStatusJob run failed', error: e.message, error_class: e.class.to_s)
    ensure
      StatsD.measure("#{STATSD_PREFIX}.duration_ms", monotonic_ms - started_ms) if started_ms
    end

    private

    # Capped, oldest-first slice with parent submissions eager-loaded (avoids an N+1).
    def pending_batch
      DigitalFormsApi::SubmissionAttempt.pending_for_polling.includes(:submission).limit(MAX_POLL_BATCH)
    end

    # Poll one attempt, isolated. The transition (bang setter) is applied HERE in the main body —
    # NOT inside a rescue clause, since an exception raised in a rescue clause escapes the method's
    # other rescues (Ruby) and would let one failed write abort the whole batch. When there is NO
    # transition, touch the attempt: pending_for_polling orders by updated_at, so bumping it moves
    # this row to the back and the queue round-robins ("least-recently-checked") instead of
    # re-polling the same oldest rows every run and starving newer ones past MAX_POLL_BATCH.
    def poll(attempt)
      decision = classify(attempt)
      if (event = decision[:event])
        attempt.public_send(event)
      else
        # Intentional: bump updated_at only for poll ordering — no validations/callbacks needed.
        attempt.touch # rubocop:disable Rails/SkipsModelValidations
      end
      track(attempt.submission.form_id, decision[:outcome], http_status: decision[:http_status])
    rescue => e
      track(attempt.submission&.form_id, 'error')
      Rails.logger.error('DigitalFormsApi::SubmissionStatusJob poll failed',
                         submission_attempt_id: attempt.id, error: e.message, error_class: e.class.to_s)
    end

    # Retrieve + infer the outcome WITHOUT transitioning (poll applies the bang setter in a
    # rescue-covered context). @return [Hash] { outcome:, event: (bang symbol or nil), http_status: }
    def classify(attempt)
      submission = attempt.submission
      return blank_id_decision(attempt) if submission.bip_submission_id.blank?

      response = service.retrieve(submission.bip_submission_id, form_id: submission.form_id)
      document_id?(response) ? { outcome: 'success', event: :accepted! } : { outcome: 'still_pending' }
    rescue Common::Client::Errors::ClientError => e
      client_error_decision(attempt, e)
    end

    # 404 is BIP's terminal "not found" -> failed; any other status is transient (stay pending, tag it).
    def client_error_decision(attempt, error)
      status = error.status
      return { outcome: 'failure', event: :failed!, http_status: status } if status == 404

      Rails.logger.warn('DigitalFormsApi::SubmissionStatusJob upstream error',
                        submission_attempt_id: attempt.id, http_status: status)
      { outcome: 'error', http_status: status }
    end

    # Defensive: bip_submission_id is nullable (presence is only guaranteed by the A2 write path);
    # never call retrieve(nil) or risk a false terminal failure. Leave pending, surface the anomaly.
    def blank_id_decision(attempt)
      Rails.logger.warn('DigitalFormsApi::SubmissionStatusJob skipped: blank bip_submission_id',
                        submission_attempt_id: attempt.id)
      { outcome: 'error' }
    end

    # @return [Boolean] whether the retrieve response carries a BIP document id (the accepted signal)
    def document_id?(response)
      response.body.dig('submission', 'document', 'documentId').present?
    end

    # Emit one POLL_METRIC increment tagged form_id + outcome (+ http_status).
    def track(form_id, outcome, http_status: nil)
      tags = ["form_id:#{form_id}", "outcome:#{outcome}"]
      tags << "http_status:#{http_status}" if http_status
      StatsD.increment(POLL_METRIC, tags:)
    end

    # @return [DigitalFormsApi::Service::Submissions] memoized BIP Forms API client for this run
    def service
      @service ||= DigitalFormsApi::Service::Submissions.new
    end

    # @return [Integer] a monotonic millisecond timestamp for duration measurement (wall-clock safe)
    def monotonic_ms
      Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
    end
  end
end
