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
              :open
            elsif open?(bucket)
              Form21aPilotAdmission.create!(user_account: user.user_account)
              :open
            else
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
