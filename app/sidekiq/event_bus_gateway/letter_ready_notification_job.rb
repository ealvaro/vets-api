# frozen_string_literal: true

require 'sidekiq'
require 'sidekiq/attr_package'
require 'claim_letters/providers/claim_letters/lighthouse_claim_letters_provider'
require_relative 'constants'
require_relative 'errors'
require_relative 'letter_ready_job_concern'
require_relative 'claim_letter_snapshot_concern'
require_relative 'letter_ready_email_job'
require_relative 'letter_ready_push_job'
require_relative 'letter_ready_sms_job'

module EventBusGateway
  class LetterReadyNotificationJob
    include Sidekiq::Job
    include LetterReadyJobConcern
    include ClaimLetterSnapshotConcern

    STATSD_METRIC_PREFIX = 'event_bus_gateway.letter_ready_notification'

    sidekiq_options retry: Constants::SIDEKIQ_RETRY_COUNT_FIRST_NOTIFICATION

    sidekiq_retries_exhausted do |msg, _ex| # rubocop:disable Cop/AttrPackageDeleteAfterRetry
      job_id = msg['jid']
      error_class = msg['error_class']
      error_message = msg['error_message']
      timestamp = Time.now.utc

      ::Rails.logger.error('LetterReadyNotificationJob retries exhausted',
                           { job_id:, timestamp:, error_class:, error_message: })
      tags = Constants::DD_TAGS + ["function: #{error_message}"]
      StatsD.increment("#{STATSD_METRIC_PREFIX}.exhausted", tags:)
    end

    def perform(participant_id, *args) # rubocop:disable Cop/AttrPackageDeleteOnSuccess
      template_ids, gate_state = normalize_perform_args(args)
      email_template_id, push_template_id, sms_template_id = template_ids.values_at('email', 'push', 'sms')

      # Fetch participant data upfront
      icn = get_icn(participant_id)

      # Snapshot the most recent claim letter at send time (logging only) and, when
      # the gated-send flag is on, decide whether a decision letter is available yet.
      # On a "miss" this re-enqueues the job on a short interval and returns without
      # sending; it returns :send when we should proceed now (letter present,
      # resolved on a re-check, or the send-anyway fallback after the attempt cap).
      return unless evaluate_send_gate(participant_id, icn, gate_state, template_ids) == :send

      # Determine which notification types are requested based on template IDs
      requested_types = requested_notification_types(email_template_id, sms_template_id, push_template_id)

      errors = []
      errors << handle_email_notification(participant_id, email_template_id, icn)
      errors << handle_sms_notification(participant_id, sms_template_id, icn)
      errors << handle_push_notification(participant_id, push_template_id, icn)
      errors.compact!

      log_completion(email_template_id, push_template_id, sms_template_id, errors)
      handle_errors(errors, requested_types, icn)

      errors
    rescue => e
      # Only catch errors from the initial BGS/MPI lookups
      if e.is_a?(Errors::BgsPersonNotFoundError) ||
         e.is_a?(Errors::MpiProfileNotFoundError) ||
         @bgs_person.nil? || @mpi_profile.nil?
        record_notification_send_failure(e, 'Notification')
      end
      raise
    end

    private

    # perform is enqueued as perform_async(participant_id, template_ids) where
    # template_ids is { 'email' => id, 'push' => id, 'sms' => id }, and re-enqueued
    # for a gated re-check as perform_in(interval, participant_id, template_ids,
    # gate_state). The legacy positional form (participant_id, email, push, sms) is
    # still accepted so jobs enqueued before this change deploys keep running;
    # remove that branch a release later once no legacy jobs remain queued. A Hash
    # first arg is unambiguously the new form (legacy template ids are strings).
    def normalize_perform_args(args)
      first = args.first
      if first.is_a?(Hash)
        [first.stringify_keys, args[1]]
      elsif args.empty?
        [{}, nil]
      else
        email, push, sms = args
        [{ 'email' => email, 'push' => push, 'sms' => sms }, nil]
      end
    end

    def requested_notification_types(email_template_id, sms_template_id, push_template_id)
      types = []
      types << 'email' if email_template_id.present?
      types << 'sms' if sms_template_id.present?
      types << 'push' if push_template_id.present?
      types
    end

    # Single BD fetch shared by send-time logging and the gated send. Logs the
    # send-time snapshot (attempt 0 only) when the logging flag is on, then, when
    # the gated-send flag is on, decides present-vs-miss. Returns :send to proceed
    # or :defer when a miss was re-enqueued. Fully guarded: any BD/logging error
    # fails open to :send so a slow or erroring Benefits Documents call can never
    # drop the notification or back up the Sidekiq queue.
    def evaluate_send_gate(participant_id, icn, gate_state, template_ids)
      return :send if icn.blank?

      logging_on = Flipper.enabled?(:event_bus_gateway_log_most_recent_claim_letter, Flipper::Actor.new(icn))
      gating_on = Flipper.enabled?(:event_bus_gateway_letter_ready_gated_send, Flipper::Actor.new(icn))
      return :send unless logging_on || gating_on

      letters = fetch_claim_letters(icn)

      # Send-time "most recent claim letter" log: attempt 0 only, independent of
      # gating (this is the original decision-letter-event arrival).
      if logging_on && gate_state.blank?
        ::Rails.logger.info('LetterReadyNotificationJob most recent claim letter',
                            most_recent_claim_letter_payload(letters))
      end

      return :send unless gating_on

      decide_gate(participant_id, letters, gate_state, template_ids)
    rescue => e
      handle_claim_letter_check_error(e, gate_state)
      :send
    end

    # Bounded BD fetch. The gated provider caps the Benefits Documents call at a
    # tight Faraday read timeout (Constants::GATED_SEND_BD_TIMEOUT_SECONDS) rather
    # than Ruby's Timeout, which isn't safe to interrupt arbitrary code in Sidekiq.
    # On a timeout Faraday raises and evaluate_send_gate rescues into a fail-open
    # send; breakers short-circuits sustained BD outages.
    def fetch_claim_letters(icn)
      user = build_user_from_icn(icn, uuid: user_account(icn)&.id)
      claim_letters_service(user).get_letters || []
    end

    # Gate decision. attempt 0 is the original send (no prior snapshot → recency
    # signal); attempts 1..N are re-checks (prior snapshot → trusted delta signal).
    def decide_gate(participant_id, letters, gate_state, template_ids)
      gate = {
        letters:,
        attempt: gate_state ? gate_state['attempt'].to_i : 0,
        prior_snapshot: gate_state && gate_state['snapshot'],
        original_sent_at: (gate_state && gate_state['original_sent_at']) || Time.current.utc.iso8601
      }

      if decision_letter_available?(letters, gate[:prior_snapshot])
        record_gate_outcome(gate[:attempt].zero? ? 'present' : 'sent_after_recheck', gate)
        return :send
      end

      return handle_gate_cap(gate) if gate[:attempt] >= Constants.gated_send_max_recheck_attempts

      defer_gated_send(participant_id, template_ids, gate)
      :defer
    end

    # After the final miss, apply the configured fallback: send anyway (default,
    # preserves today's behavior) or hold (single Settings switch, no rewrite).
    def handle_gate_cap(gate)
      if Constants.gated_send_fallback_send_anyway?
        record_gate_outcome('sent_anyway', gate)
        :send
      else
        record_gate_outcome('held', gate)
        :defer
      end
    end

    # Re-enqueue the parent on the configured interval, carrying attempt count,
    # original send time, and the send-time snapshot. The snapshot is captured once
    # at attempt 0 and passed unchanged so the delta is always measured against the
    # send-time state (string keys survive the Sidekiq JSON round-trip). The SMS
    # blackout window is still honored downstream by LetterReadySmsJob's own
    # perform_at deferral when the send finally fires, so re-checks don't reintroduce
    # the blackout retry gap.
    def defer_gated_send(participant_id, template_ids, gate)
      snapshot = if gate[:attempt].zero?
                   decision_letter_snapshot(gate[:letters]).transform_keys(&:to_s)
                 else
                   gate[:prior_snapshot]
                 end
      next_state = { 'attempt' => gate[:attempt] + 1, 'original_sent_at' => gate[:original_sent_at],
                     'snapshot' => snapshot }

      self.class.perform_in(Constants.gated_send_recheck_interval_minutes.minutes,
                            participant_id, template_ids, next_state)
      record_gate_outcome('deferred', gate)
    end

    def most_recent_claim_letter_payload(letters)
      most_recent = most_recent_letter(letters)

      most_recent_details = {
        message_type: 'ebg.letter_ready.most_recent_claim_letter',
        most_recent_received_at: format_letter_date(most_recent&.dig(:received_at)),
        most_recent_upload_date: format_letter_date(most_recent&.dig(:upload_date)),
        most_recent_doc_type: most_recent&.dig(:doc_type),
        most_recent_type_description: most_recent&.dig(:type_description),
        most_recent_document_id: most_recent&.dig(:document_id)
      }

      decision_letter_snapshot(letters).merge(most_recent_details)
    end

    # Structured gate log + metrics. Preserves the delta / recency / lag signals
    # from the retired measurement job, now tagged with the gate outcome and attempt
    # so ramp behavior and realized BD load are observable against the ~25K/day base.
    def record_gate_outcome(outcome, gate)
      current = decision_letter_snapshot(gate[:letters])
      signals = {
        current:,
        delta: gate[:prior_snapshot].present? ? new_decision_letter?(current, gate[:prior_snapshot]) : nil,
        recent: recent_decision_letter?(gate[:letters]),
        seconds: seconds_since(gate[:original_sent_at])
      }

      ::Rails.logger.info('LetterReadyNotificationJob gated send', gated_send_payload(outcome, gate, signals))
      emit_gate_metrics(outcome, gate[:attempt], signals)
    end

    def gated_send_payload(outcome, gate, signals)
      current = signals[:current]
      prior_snapshot = gate[:prior_snapshot] || {}
      {
        message_type: 'ebg.letter_ready.gated_send',
        gate_outcome: outcome,
        attempt: gate[:attempt],
        max_attempts: Constants.gated_send_max_recheck_attempts,
        seconds_since_original: signals[:seconds],
        new_decision_letter_since_snapshot: signals[:delta],
        recent_decision_letter_present: signals[:recent],
        decision_letter_present: current[:decision_letter_count].positive?,
        decision_letter_count: current[:decision_letter_count],
        most_recent_decision_received_at: current[:most_recent_decision_received_at],
        most_recent_decision_document_id: current[:most_recent_decision_document_id],
        snapshot_decision_letter_count: prior_snapshot['decision_letter_count'],
        snapshot_most_recent_decision_document_id: prior_snapshot['most_recent_decision_document_id']
      }
    end

    def emit_gate_metrics(outcome, attempt, signals)
      tags = Constants::DD_TAGS + [
        "gate_outcome:#{outcome}",
        "attempt:#{attempt}",
        "recency:#{signals[:recent] ? 'present' : 'absent'}"
      ]
      tags << "delta:#{signals[:delta] ? 'found' : 'not_found'}" unless signals[:delta].nil?

      StatsD.increment("#{STATSD_METRIC_PREFIX}.gate", tags:)
      return unless signals[:seconds] && %w[sent_after_recheck sent_anyway].include?(outcome)

      # Lag from the original send to resolution, in seconds — only meaningful when
      # a deferred send actually resolved (or fell back), so the p50/p95 aren't
      # diluted by the attempt-0 "present" cases.
      StatsD.measure("#{STATSD_METRIC_PREFIX}.gate_time_since_original", signals[:seconds], tags:)
    end

    def handle_claim_letter_check_error(error, gate_state)
      ::Rails.logger.warn(
        'LetterReadyNotificationJob claim letter check failed; sending',
        {
          attempt: gate_state ? gate_state['attempt'] : 0,
          error_class: error.class.name,
          error_message: Logging::Helper::DataScrubber.scrub(error.message)
        }
      )
      tags = Constants::DD_TAGS + ["error:#{error.class.name}"]
      StatsD.increment("#{STATSD_METRIC_PREFIX}.claim_letter_check_failure", tags:)
      nil
    end

    def should_send_email?(email_template_id, icn)
      email_template_id.present? && icn.present?
    end

    def should_send_push?(push_template_id, icn)
      push_template_id.present? && icn.present?
    end

    def should_send_sms?(sms_template_id, icn)
      sms_template_id.present? && icn.present?
    end

    def handle_email_notification(participant_id, email_template_id, icn)
      if should_send_email?(email_template_id, icn)
        first_name = get_first_name_from_participant_id(participant_id)

        if first_name.present?
          send_email_async(participant_id, email_template_id, first_name, icn)
        else
          log_notification_skipped('email', 'first_name not present', email_template_id)
          nil
        end
      else
        log_notification_skipped('email', 'ICN or template not available', email_template_id)
        nil
      end
    end

    def handle_sms_notification(participant_id, sms_template_id, icn)
      unless should_send_sms?(sms_template_id, icn)
        log_notification_skipped('sms', 'ICN or template not available', sms_template_id)
        return nil
      end

      unless Flipper.enabled?(:event_bus_gateway_letter_ready_sms_notifications, Flipper::Actor.new(icn))
        log_notification_skipped('sms', 'SMS notifications not enabled for this user', sms_template_id)
        return nil
      end

      send_sms_async(participant_id, sms_template_id, icn)
    end

    def handle_push_notification(participant_id, push_template_id, icn)
      unless should_send_push?(push_template_id, icn)
        log_notification_skipped('push', 'ICN or template not available', push_template_id)
        return nil
      end

      unless Flipper.enabled?(:event_bus_gateway_letter_ready_push_notifications, Flipper::Actor.new(icn))
        log_notification_skipped('push', 'Push notifications not enabled for this user', push_template_id)
        return nil
      end

      send_push_async(participant_id, push_template_id, icn)
    end

    def send_email_async(participant_id, email_template_id, first_name, icn)
      # Store PII in Redis and pass only cache key to avoid PII exposure in logs
      cache_key = Sidekiq::AttrPackage.create(first_name:, icn:)
      LetterReadyEmailJob.perform_async(participant_id, email_template_id, cache_key)
      nil
    rescue => e
      log_notification_failure('email', email_template_id, e)
      { type: 'email', error: e.message }
    end

    def send_sms_async(participant_id, sms_template_id, icn)
      # Store PII in Redis and pass only cache key to avoid PII exposure in logs
      cache_key = Sidekiq::AttrPackage.create(icn:)
      LetterReadySmsJob.perform_async(participant_id, sms_template_id, cache_key)
      nil
    rescue => e
      log_notification_failure('sms', sms_template_id, e)
      { type: 'sms', error: e.message }
    end

    def send_push_async(participant_id, push_template_id, icn)
      # Store PII in Redis and pass only cache key to avoid PII exposure in logs
      cache_key = Sidekiq::AttrPackage.create(icn:)
      LetterReadyPushJob.perform_async(participant_id, push_template_id, cache_key)
      nil
    rescue => e
      log_notification_failure('push', push_template_id, e)
      { type: 'push', error: e.message }
    end

    def log_notification_failure(notification_type, template_id, error)
      ::Rails.logger.error(
        "LetterReadyNotificationJob #{notification_type} enqueue failed",
        {
          notification_type:,
          template_id:,
          error_class: error.class.name,
          error_message: error.message
        }
      )

      # Track enqueuing failures (different from send failures tracked in child jobs)
      tags = Constants::DD_TAGS + [
        "notification_type:#{notification_type}",
        "error:#{error.class.name}"
      ]
      StatsD.increment("#{STATSD_METRIC_PREFIX}.enqueue_failure", tags:)
    end

    def log_notification_skipped(notification_type, reason, template_id)
      ::Rails.logger.error(
        "LetterReadyNotificationJob #{notification_type} skipped",
        {
          notification_type:,
          reason:,
          template_id:
        }
      )

      tags = Constants::DD_TAGS + [
        "notification_type:#{notification_type}",
        "reason:#{reason.parameterize.underscore}"
      ]
      StatsD.increment("#{STATSD_METRIC_PREFIX}.skipped", tags:)
    end

    def log_completion(email_template_id, push_template_id, sms_template_id, errors)
      successful_notifications = []
      successful_notifications << 'email' if email_template_id.present? && errors.none? { |e| e[:type] == 'email' }
      successful_notifications << 'push' if push_template_id.present? && errors.none? { |e| e[:type] == 'push' }
      successful_notifications << 'sms' if sms_template_id.present? && errors.none? { |e| e[:type] == 'sms' }

      failed_messages = errors.map { |h| "#{h[:type]}: #{h[:error]}" }.join(', ')

      ::Rails.logger.info(
        'LetterReadyNotificationJob completed',
        {
          notifications_sent: successful_notifications.join(', '),
          notifications_failed: failed_messages,
          email_template_id:,
          push_template_id:,
          sms_template_id:
        }
      )
    end

    def handle_errors(errors, requested_types, icn)
      return if errors.empty?

      failed_types = errors.map { |e| e[:type] }

      # Filter requested types by feature flags (some may have been skipped)
      # SMS and push may not be attempted even if template_id was provided if feature flag is off
      actually_requested_types = filter_by_feature_flags(requested_types, icn)

      # Check if all requested (and not feature-flag-skipped) notifications failed
      if actually_requested_types.present? && (failed_types.to_set == actually_requested_types.to_set)
        # All actually requested notifications failed to enqueue
        error_details = errors.map { |e| "#{e[:type]}: #{e[:error]}" }.join('; ')
        raise Errors::NotificationEnqueueError, "All notifications failed to enqueue: #{error_details}"
      else
        # Partial failure - some succeeded
        successful_types = actually_requested_types - failed_types
        error_messages = errors.map { |h| "#{h[:type]}: #{h[:error]}" }.join(', ')

        ::Rails.logger.warn(
          'LetterReadyNotificationJob partial failure',
          {
            successful: successful_types.join(', '),
            failed: error_messages
          }
        )
      end
    end

    def filter_by_feature_flags(requested_types, icn)
      actually_requested_types = requested_types.dup

      if requested_types.include?('sms') &&
         !Flipper.enabled?(:event_bus_gateway_letter_ready_sms_notifications, Flipper::Actor.new(icn))
        actually_requested_types.delete('sms')
      end

      if requested_types.include?('push') &&
         !Flipper.enabled?(:event_bus_gateway_letter_ready_push_notifications, Flipper::Actor.new(icn))
        actually_requested_types.delete('push')
      end

      actually_requested_types
    end
  end
end
