# frozen_string_literal: true

module UnifiedHealthData
  module Adapters
    # Measurement-only "submitted stuck > 3 days" signal for Oracle Health.
    # OH collapses "submitted" after the 3-day in-flight window (refill_submit_date is
    # dropped), so a refill requested but never dispensed is invisible to a post-adapter
    # status scan. Detect it here from the raw order-Task and emit it into the shared
    # api.uhd.prescriptions.stuck.submitted metric with source_ehr:OH. Never mutates
    # classification. All logged fields are PII/PHI-safe.
    #
    # Guarded by the :mhv_medications_stuck_status_logging Flipper flag (default off).
    #
    # Depends on methods provided by the including adapter / its other mixins:
    # - most_recent_contained_task, valid_task_date?, subsequent_dispense? (OracleHealthTaskHelper)
    # - days_between, bucket_days, rx_id_hash (OracleHealthRefillWindowLoggingFormatters)
    # - parse_date_or_epoch (DateTimeHelpers)
    # - extract_station_number (OracleHealthPrescriptionAdapter)
    # - @current_user
    module OracleHealthStuckStatusLoggingHelper
      STUCK_SUBMITTED_STATSD = 'api.uhd.prescriptions.stuck.submitted'
      STUCK_SUBMITTED_TOTAL_STATSD = 'api.uhd.prescriptions.stuck.submitted_total'
      STUCK_LOG_MESSAGE = 'UHD prescription stuck status'

      # @param resource [Hash] FHIR MedicationRequest resource
      # @param dispenses_data [Array<Hash>] Parsed dispense data
      def log_oh_submitted_stuck(resource, dispenses_data)
        return unless Flipper.enabled?(:mhv_medications_stuck_status_logging, @current_user)

        task = most_recent_contained_task(
          resource, intent: 'order', statuses: [OracleHealthTaskHelper::REFILL_SUBMITTED_TASK_STATUS]
        )
        return unless task

        submit_date = task.dig('executionPeriod', 'start')
        return unless valid_task_date?(submit_date)
        return if subsequent_dispense?(submit_date, dispenses_data)

        # Count every in-flight OH "submitted" refill here (the post-adapter scan can't: OH drops
        # the submit date), so the OH stuck rate's numerator and denominator share one producer.
        StatsD.increment(STUCK_SUBMITTED_TOTAL_STATSD, tags: ['source_ehr:OH'])

        days = days_between(parse_date_or_epoch(submit_date), Time.current)
        return unless days && days > OracleHealthTaskHelper::REFILL_IN_FLIGHT_WINDOW_DAYS

        emit_oh_submitted_stuck(resource, days)
      rescue => e
        Rails.logger.error("OH submitted stuck logging error: #{e.message}")
      end

      private

      def emit_oh_submitted_stuck(resource, days)
        StatsD.increment(
          STUCK_SUBMITTED_STATSD,
          tags: ['source_ehr:OH', "days_bucket:#{bucket_days(days)}"]
        )
        Rails.logger.info(
          message: STUCK_LOG_MESSAGE,
          service: 'unified_health_data',
          metric: 'submitted',
          source_ehr: 'OH',
          rx_id_hash: rx_id_hash(resource['id']),
          station_number: extract_station_number(resource),
          days_stuck: days,
          days_bucket: bucket_days(days),
          user_uuid: @current_user&.uuid
        )
      end
    end
  end
end
