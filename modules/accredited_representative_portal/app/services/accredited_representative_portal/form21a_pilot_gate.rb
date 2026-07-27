# frozen_string_literal: true

module AccreditedRepresentativePortal
  # Single source of truth for the Form 21a limited-release pilot gating rules.
  #
  # Two calls model the pilot lifecycle:
  #   * `status` (call 1) — a read-only snapshot the frontend reads before rendering the form.
  #   * `admit!`  (call 2) — the authoritative slot consumption, fired when the user starts a
  #                          new draft. Enforces the exact monthly cap under an advisory lock.
  #
  # Already-admitted users always pass (resume/submit) regardless of the month or the cap.
  # The cap window is the current calendar month in the fixed (Eastern) timezone, so it
  # resets implicitly with no cron.
  class Form21aPilotGate
    MONTHLY_LIMIT = 50
    TIMEZONE = 'America/New_York'

    # StatsD counters emitted inline at event time. Product/OGC visibility (admissions this
    # month, remaining slots, in-progress, submitted, gate open/closed) is derived query-side
    # in Datadog by summing these counters over an Eastern-month window; no gauges or backend
    # aggregation job are required.
    #
    # STATSD_ADMISSION is tagged outcome:open (a new slot was consumed) or outcome:closed (the
    # cap was reached and the user was turned away). Idempotent re-entry by an already-admitted
    # user emits nothing so the admissions-this-month sum stays accurate.
    STATSD_ADMISSION = 'api.form21a.pilot.admission'
    STATSD_SUBMISSION = 'api.form21a.pilot.submission'

    class << self
      # Call 1 (read-only): the state payload the frontend reads before rendering the form.
      # Writes nothing.
      def status(user)
        limit = MONTHLY_LIMIT
        count = admissions_this_month
        available = admitted?(user) || count < limit

        {
          state: available ? 'open' : 'closed',
          admissions_this_month: count,
          monthly_limit: limit,
          remaining: [limit - count, 0].max
        }
      end

      # Call 2 (authoritative): consumes a slot for the user. Idempotent per user.
      #
      # Returns :open when the user may proceed, :closed when this month's cap is reached.
      #
      # The count-and-create runs inside a transaction-scoped advisory lock (keyed on the
      # Eastern month) so the cap is exact under concurrency. The whole body is wrapped in a
      # transaction so the `pg_advisory_xact_lock` spans the count+create even when no outer
      # transaction is open; when a caller already has one (e.g. the in-progress-form save),
      # this joins it, so the lock is held until that outer transaction commits and the new
      # row rolls back atomically alongside the caller's work.
      def admit!(user)
        ActiveRecord::Base.transaction do
          # Compute the Eastern "now" once so the advisory lock key and the month count
          # always resolve to the same calendar month, even across a month rollover.
          bucket = current_bucket
          Form21aPilotAdmission.with_advisory_lock(advisory_lock_key(bucket), transaction: true) do
            if admitted?(user)
              # Idempotent re-entry: already counted when first admitted. Emit nothing.
              :open
            elsif open?(bucket)
              Form21aPilotAdmission.create!(user_account: user.user_account)
              # Emit only after the surrounding transaction actually commits. admit! runs inside
              # the caller's transaction (see InProgressFormsController#admit_and_persist); if that
              # transaction later rolls back (e.g. the draft save fails), the admission row is
              # undone, so deferring keeps sum(outcome:open) an accurate count of real admissions.
              emit_admission_counter_after_commit('outcome:open')
              :open
            else
              # The caller rolls back the transaction on :closed, so an after_commit callback would
              # be discarded. Emit inline — the "turned away" event is real regardless of rollback.
              emit_admission_counter('outcome:closed')
              :closed
            end
          end
        end
      end

      # Has this user ever been admitted? Admitted users always pass, regardless of month or cap.
      def admitted?(user)
        Form21aPilotAdmission.exists?(user_account_id: user.user_account.id)
      end

      # Is there an open slot in the current Eastern calendar month? Read-only.
      def open?(bucket = current_bucket)
        admissions_this_month(bucket) < MONTHLY_LIMIT
      end

      private

      # Defers admission telemetry until the surrounding transaction commits, so a caller
      # rollback cannot leave an over-counted admission. current_transaction returns the open
      # transaction (bubbling to the outermost) or a no-op transaction that fires immediately
      # when none is open.
      def emit_admission_counter_after_commit(outcome)
        ActiveRecord::Base.current_transaction.after_commit { emit_admission_counter(outcome) }
      end

      # Best-effort telemetry: a StatsD failure must never roll back the admission or error
      # the gate, so emission is rescued (mirrors lib/statsd_middleware.rb).
      def emit_admission_counter(outcome)
        StatsD.increment(STATSD_ADMISSION, tags: [outcome])
      rescue => e
        Rails.logger.warn('Form21aPilotGate: admission telemetry failed', exception: e)
      end

      def current_bucket
        Time.current.in_time_zone(TIMEZONE)
      end

      def admissions_this_month(bucket = current_bucket)
        Form21aPilotAdmission.where(created_at: bucket.all_month).count
      end

      def advisory_lock_key(bucket = current_bucket)
        "form21a_pilot_admit_#{bucket.strftime('%Y-%m')}"
      end
    end
  end
end
