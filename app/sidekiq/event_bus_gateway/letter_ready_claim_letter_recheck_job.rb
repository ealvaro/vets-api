# frozen_string_literal: true

require 'sidekiq'
require 'claim_letters/providers/claim_letters/lighthouse_claim_letters_provider'
require_relative 'constants'
require_relative 'errors'
require_relative 'letter_ready_job_concern'
require_relative 'claim_letter_snapshot_concern'

module EventBusGateway
  # Measurement-only job. Enqueued by LetterReadyNotificationJob at one or more
  # deferred intervals to re-query Benefits Documents and record whether a recent
  # decision letter (doc-type 184) has become available since the notification
  # fired, plus the delta versus the send-time snapshot. This builds the
  # claim-letter propagation-lag distribution in DataDog so we can tune a real
  # mitigation. It never affects the notification flow: it retries nothing and
  # swallows all errors.
  class LetterReadyClaimLetterRecheckJob
    include Sidekiq::Job
    include LetterReadyJobConcern
    include ClaimLetterSnapshotConcern

    STATSD_METRIC_PREFIX = 'event_bus_gateway.letter_ready_claim_letter_recheck'

    # Measurement job: do not retry. A missed sample is acceptable and must never
    # back up the Sidekiq queue or affect the notification path.
    sidekiq_options retry: false

    def perform(participant_id, original_sent_at_iso, interval_label, snapshot = {})
      icn = get_icn(participant_id)
      return if icn.blank?
      return unless Flipper.enabled?(:event_bus_gateway_claim_letter_recheck, Flipper::Actor.new(icn))

      user = build_user_from_icn(icn, uuid: user_account(icn)&.id)
      letters = claim_letters_service(user).get_letters || []

      log_recheck_result(letters, original_sent_at_iso, interval_label, snapshot || {})
    rescue => e
      handle_recheck_error(e, interval_label)
    end

    private

    def log_recheck_result(letters, original_sent_at_iso, interval_label, snapshot)
      current = decision_letter_snapshot(letters)
      # Two candidate "available" definitions, logged side by side so the data can
      # tell us which makes the better gate (see story open question):
      #   delta   — a new decision letter appeared vs. the send-time snapshot
      #   recency — any decision letter is stamped within the recency window now
      signals = {
        interval_label:,
        seconds_since_original: seconds_since(original_sent_at_iso),
        new_letter: new_decision_letter?(current, snapshot),
        recent: recent_decision_letter?(letters)
      }

      ::Rails.logger.info('LetterReadyClaimLetterRecheckJob claim letter recheck',
                          recheck_payload(current, snapshot, signals))
      emit_recheck_metrics(signals)
    end

    def recheck_payload(current, snapshot, signals)
      recency_window_days = (Constants::CLAIM_LETTER_RECENCY_WINDOW / 1.day).to_i
      {
        message_type: 'ebg.letter_ready.claim_letter_recheck',
        interval_label: signals[:interval_label],
        seconds_since_original: signals[:seconds_since_original],
        new_decision_letter_since_snapshot: signals[:new_letter],
        recent_decision_letter_present: signals[:recent],
        recency_window_days:,
        decision_letter_present: current[:decision_letter_count].positive?,
        decision_letter_count: current[:decision_letter_count],
        most_recent_decision_received_at: current[:most_recent_decision_received_at],
        most_recent_decision_document_id: current[:most_recent_decision_document_id],
        snapshot_decision_letter_count: snapshot['decision_letter_count'],
        snapshot_most_recent_decision_received_at: snapshot['most_recent_decision_received_at'],
        snapshot_most_recent_decision_document_id: snapshot['most_recent_decision_document_id']
      }
    end

    # A decision letter has "appeared" when the decision-letter set changed since
    # the send-time snapshot — any document id present now that wasn't at send
    # time. Keys off the changing set rather than past-vs-future of a single
    # received_at, which is an unreliable wall-clock signal (see story constraint
    # #2). Falls back to a rise in count when ids are unavailable, and to plain
    # presence when no snapshot was carried.
    def new_decision_letter?(current, snapshot)
      return current[:decision_letter_count].positive? if snapshot.blank?

      prior_ids = Array(snapshot['decision_letter_document_ids'])
      current_ids = Array(current[:decision_letter_document_ids])
      return true if (current_ids - prior_ids).any?

      current[:decision_letter_count] > snapshot['decision_letter_count'].to_i
    end

    def emit_recheck_metrics(signals)
      # Two dimensions on one counter so either "available" definition (or their
      # agreement) can be sliced in DataDog without a second metric.
      tags = Constants::DD_TAGS + [
        "interval:#{signals[:interval_label]}",
        "delta:#{signals[:new_letter] ? 'found' : 'not_found'}",
        "recency:#{signals[:recent] ? 'present' : 'absent'}"
      ]

      StatsD.increment("#{STATSD_METRIC_PREFIX}.result", tags:)
      return unless signals[:seconds_since_original]

      StatsD.measure("#{STATSD_METRIC_PREFIX}.time_since_original", signals[:seconds_since_original], tags:)
    end

    def seconds_since(iso)
      return nil if iso.blank?

      (Time.current - Time.zone.parse(iso.to_s)).to_i
    rescue ArgumentError, TypeError
      nil
    end

    def handle_recheck_error(error, interval_label)
      ::Rails.logger.warn(
        'LetterReadyClaimLetterRecheckJob failed to recheck claim letter',
        {
          interval_label:,
          error_class: error.class.name,
          error_message: Logging::Helper::DataScrubber.scrub(error.message)
        }
      )
      tags = Constants::DD_TAGS + ["interval:#{interval_label}", "error:#{error.class.name}"]
      StatsD.increment("#{STATSD_METRIC_PREFIX}.failure", tags:)
      nil
    end
  end
end
