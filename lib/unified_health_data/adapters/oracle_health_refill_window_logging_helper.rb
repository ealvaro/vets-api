# frozen_string_literal: true

require 'digest'
require_relative 'oracle_health_task_helper'

module UnifiedHealthData
  module Adapters
    # Measurement-only instrumentation for the Oracle Health in-flight refill
    # "window" behavior. Designed to be included in OracleHealthPrescriptionAdapter.
    #
    # Guarded by the :mhv_medications_oh_refill_window_logging Flipper flag (default
    # off). Emits measurement events for OH MedicationRequests that carry an honored
    # in-flight order-Task so we can characterize how long refills actually take to
    # fill and how often in-flight refills age past the staleness window without ever
    # being dispensed.
    #
    # This module is strictly side-effect-free with respect to classification: it only
    # reads the already-computed prescription attributes and dispense data and never
    # mutates them. All logged fields are PII/PHI-safe (the raw prescription id is
    # one-way hashed; drug name, sig, prescription number, patient identifiers and
    # facility names are never logged).
    #
    # Depends on methods provided by the including adapter / its other mixins:
    # - most_recent_contained_task, valid_task_date?, honored_refill_statuses,
    #   subsequent_dispense? (OracleHealthTaskHelper)
    # - parse_date_or_epoch (DateTimeHelpers)
    # - extract_station_number (OracleHealthPrescriptionAdapter)
    # - @current_user
    module OracleHealthRefillWindowLoggingHelper
      REFILL_WINDOW_LOG_MESSAGE = 'OH in-flight refill window measurement'
      STATSD_WINDOW_DROPPED = 'api.uhd.oh_refill.window_dropped'
      STATSD_DISPENSE_CLEARED = 'api.uhd.oh_refill.dispense_cleared'
      STATION_NUMBER_EXTENSION_URL = 'http://va.gov/mhv/rx/station-number'

      # @param resource [Hash] FHIR MedicationRequest resource
      # @param attributes [Hash] The fully-built prescription attributes (read only)
      # @param dispenses_data [Array<Hash>] Parsed dispense data
      def log_refill_window_measurement(resource, attributes, dispenses_data)
        return unless Flipper.enabled?(:mhv_medications_oh_refill_window_logging, @current_user)

        task = most_recent_contained_task(resource, intent: 'order', statuses: honored_refill_statuses)
        return unless task

        task_submit_date = task.dig('executionPeriod', 'start')
        return unless valid_task_date?(task_submit_date)

        emit_refill_window_event(resource, attributes, task, task_submit_date, dispenses_data)
      rescue => e
        Rails.logger.error("OH refill window logging error: #{e.message}")
      end

      private

      # Decides which measurement event applies and emits it.
      # (B) dispense-cleared: a completed dispense arrived after the Task submit date.
      # (A) window-dropped: no subsequent dispense and the Task is older than the window.
      def emit_refill_window_event(resource, attributes, task, task_submit_date, dispenses_data)
        submit_time = parse_date_or_epoch(task_submit_date)
        days_since_submit = days_between(submit_time, Time.current)

        if subsequent_dispense?(task_submit_date, dispenses_data)
          fill_time = completed_dispense_times(dispenses_data).select { |t| t > submit_time }.min
          days_to_dispense = days_between(submit_time, fill_time)
          event = { days_since_submit:, has_subsequent_dispense: true, days_to_dispense: }
          payload = refill_window_payload(resource, attributes, task, event)

          StatsD.increment(STATSD_DISPENSE_CLEARED, tags: refill_window_tags(payload, days_to_dispense))
          Rails.logger.info(payload.merge(event: 'dispense_cleared'))
        elsif days_since_submit && days_since_submit > OracleHealthTaskHelper::REFILL_IN_FLIGHT_WINDOW_DAYS
          event = { days_since_submit:, has_subsequent_dispense: false, days_to_dispense: nil }
          payload = refill_window_payload(resource, attributes, task, event)

          StatsD.increment(STATSD_WINDOW_DROPPED, tags: refill_window_tags(payload, days_since_submit))
          Rails.logger.info(payload.merge(event: 'window_dropped'))
        end
      end

      # Builds the PII/PHI-safe correlation/context portion of the log payload and
      # merges in the timing fields.
      # @param event [Hash] :days_since_submit, :has_subsequent_dispense, :days_to_dispense
      def refill_window_payload(resource, attributes, task, event)
        {
          message: REFILL_WINDOW_LOG_MESSAGE,
          service: 'unified_health_data',
          source_system: 'oracle-health',
          rx_id_hash: rx_id_hash(resource['id']),
          station_number: refill_window_station_number(resource, task),
          task_status: task['status'],
          task_intent: task['intent'],
          task_type: refill_task_type(task),
          is_refillable: attributes[:is_refillable],
          flag_enabled: Flipper.enabled?(:mhv_medications_management_improvements, @current_user)
        }.merge(refill_window_timing(resource, task, event))
      end

      # PII/PHI-safe timing fields for the log payload.
      def refill_window_timing(resource, task, event)
        supply = resource.dig('dispenseRequest', 'expectedSupplyDuration') || {}
        {
          task_submit_date: task.dig('executionPeriod', 'start'),
          days_since_submit: event[:days_since_submit],
          expected_supply_duration_value: supply['value'],
          expected_supply_duration_unit: supply['unit'],
          validity_period_end: resource.dig('dispenseRequest', 'validityPeriod', 'end'),
          days_to_dispense: event[:days_to_dispense],
          has_subsequent_dispense: event[:has_subsequent_dispense]
        }
      end

      # StatsD tags: cheap aggregate dimensions only (no PII/PHI).
      def refill_window_tags(payload, days)
        [
          "flag_enabled:#{payload[:flag_enabled]}",
          "task_type:#{payload[:task_type]}",
          "days_bucket:#{bucket_days(days)}"
        ]
      end

      # Prefers the station number from the Task meta extension (available even when
      # no dispense exists yet); falls back to the dispense-derived station number.
      def refill_window_station_number(resource, task)
        task_meta_value(task, STATION_NUMBER_EXTENSION_URL).presence || extract_station_number(resource)
      end

      # order-Task type: honors the task-type meta extension, defaults to 'refill'.
      def refill_task_type(task)
        task_meta_value(task, OracleHealthTaskHelper::TASK_TYPE_EXTENSION_URL).presence || 'refill'
      end

      def task_meta_value(task, url)
        (task.dig('meta', 'extension') || []).find { |e| e['url'] == url }&.dig('valueString')
      end

      # One-way SHA256 hash of the raw prescription id. Never log the raw id.
      def rx_id_hash(id)
        return nil if id.blank?

        Digest::SHA256.hexdigest(id.to_s)
      end

      def days_between(from_time, to_time)
        return nil if from_time.nil? || to_time.nil?

        ((to_time - from_time) / 1.day).floor
      end

      # Bucketed day ranges for low-cardinality StatsD tagging.
      def bucket_days(days)
        return 'unknown' if days.nil?

        case days
        when ..3 then '0-3'
        when 4..7 then '4-7'
        when 8..14 then '8-14'
        when 15..30 then '15-30'
        else '30+'
        end
      end

      # Parsed fill times of completed dispenses (both whenPrepared and whenHandedOver).
      def completed_dispense_times(dispenses_data)
        dispenses_data.select { |d| d[:status] == 'completed' }.flat_map do |d|
          [d[:when_prepared], d[:when_handed_over]].compact_blank.map { |raw| parse_date_or_epoch(raw) }
        end
      end
    end
  end
end
