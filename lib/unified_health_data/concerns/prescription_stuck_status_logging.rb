# frozen_string_literal: true

require 'digest'
require_relative '../constants'
require_relative 'prescription_stuck_status_formatters'

module UnifiedHealthData
  module Concerns
    # Emits "stuck status" metrics for prescriptions that have not progressed within
    # expected windows:
    #   - "Active: Submitted" stuck longer than SUBMITTED_STUCK_DAYS (never dispensed)
    #   - "Active: Refill in Process" stuck longer than REFILL_IN_PROCESS_STUCK_DAYS
    #     since the refill was requested
    #
    # Caveats surfaced during design:
    #   - Refill-in-process without tracking is not necessarily "stuck": an in-person
    #     window/counter pickup never receives tracking. For VistA we therefore only
    #     count CMOP/mail fills (cmop_* present). Oracle Health has no CMOP signal yet,
    #     so its window pickups cannot be excluded; OH is counted but tagged
    #     source_ehr:OH so the noisier series can be isolated in Datadog.
    #   - Oracle Health collapses "submitted" after its 3-day in-flight window
    #     (refill_submit_date is dropped), so an OH submitted-stuck refill is invisible
    #     to this post-adapter scan. That case is emitted from the OH adapter during
    #     parse (OracleHealthPrescriptionAdapter#log_oh_submitted_stuck) into the same
    #     api.uhd.prescriptions.stuck.submitted metric with source_ehr:OH.
    module PrescriptionStuckStatusLogging
      include PrescriptionStuckStatusFormatters

      # Mirrors the OH adapter's OracleHealthTaskHelper::REFILL_IN_FLIGHT_WINDOW_DAYS
      # (its OH-specific equivalent). Kept separate because this scan also covers VistA;
      # the two must stay in sync.
      SUBMITTED_STUCK_DAYS = 3
      # Kept below PrescriptionsAdapter::CMOP_IN_PROCESS_WINDOW_DEFAULT_DAYS (15) so a
      # bridge-driven refill in process is still observable before the bridge flips it back
      # to "Active"; also mirrors the frontend's 7-day "taking longer than expected" window.
      REFILL_IN_PROCESS_STUCK_DAYS = 7

      STUCK_LOG_MESSAGE = 'UHD prescription stuck status'

      # STATSD_SUBMITTED must remain identical to the OH adapter's
      # OracleHealthStuckStatusLoggingHelper::STUCK_SUBMITTED_STATSD, which feeds the same
      # series for OH submitted-stuck refills.
      STATSD_SUBMITTED = 'api.uhd.prescriptions.stuck.submitted'
      STATSD_REFILL_IN_PROCESS = 'api.uhd.prescriptions.stuck.refill_in_process'
      STATSD_SUBMITTED_TOTAL = 'api.uhd.prescriptions.stuck.submitted_total'
      STATSD_REFILL_IN_PROCESS_TOTAL = 'api.uhd.prescriptions.stuck.refill_in_process_total'

      METRIC_SUBMITTED = 'submitted'
      METRIC_REFILL_IN_PROCESS = 'refill_in_process'

      STATUS_SUBMITTED = UnifiedHealthData::Constants::PrescriptionStatuses::STATUS_SUBMITTED
      STATUS_REFILL_IN_PROCESS = UnifiedHealthData::Constants::PrescriptionStatuses::STATUS_REFILL_IN_PROCESS

      # @param prescriptions [Array<UnifiedHealthData::Prescription>] the fully-parsed list
      def log_stuck_status_metrics(prescriptions)
        return unless Flipper.enabled?(:mhv_medications_stuck_status_logging, @user)

        list = Array(prescriptions)
        emit_stuck_submitted_totals(list)
        emit_stuck_refill_in_process_totals(list)

        list.each do |rx|
          if submitted_stuck?(rx)
            emit_stuck(STATSD_SUBMITTED, METRIC_SUBMITTED, rx, submitted_stuck_days(rx))
          elsif refill_in_process_stuck?(rx)
            emit_stuck(STATSD_REFILL_IN_PROCESS, METRIC_REFILL_IN_PROCESS, rx, refill_in_process_stuck_days(rx))
          end
        end
      rescue => e
        Rails.logger.warn(
          'UHD prescription stuck status logging failed',
          error_class: e.class.name,
          error_message: e.message.to_s
        )
      end

      private

      # Emits the count of all "submitted" prescriptions per source.
      def emit_stuck_submitted_totals(list)
        # OH "submitted" is counted at parse time (submit date dropped post-parse); skip it here.
        non_oh = list.reject { |rx| rx.source_ehr == UnifiedHealthData::Prescription::SOURCE_EHR_ORACLE_HEALTH }
        emit_status_totals(non_oh, STATUS_SUBMITTED, STATSD_SUBMITTED_TOTAL)
      end

      # Emits the count of all "refill in process" prescriptions per source.
      def emit_stuck_refill_in_process_totals(list)
        emit_status_totals(list, STATUS_REFILL_IN_PROCESS, STATSD_REFILL_IN_PROCESS_TOTAL)
      end

      def emit_status_totals(list, status, metric)
        list.group_by { |rx| stuck_source_tag(rx) }.each do |source, rxs|
          count = rxs.count { |rx| rx.refill_status == status }
          next unless count.positive?

          StatsD.increment(metric, count, tags: ["source_ehr:#{source}"])
        end
      end

      def emit_stuck(statsd_metric, metric_label, rx, days)
        tags = ["source_ehr:#{stuck_source_tag(rx)}", "days_bucket:#{stuck_days_bucket(days)}"]
        StatsD.increment(statsd_metric, tags:)
        Rails.logger.info(
          message: STUCK_LOG_MESSAGE,
          service: 'unified_health_data',
          metric: metric_label,
          source_ehr: stuck_source_tag(rx),
          rx_id_hash: stuck_rx_id_hash(rx.id),
          station_number: rx.station_number,
          days_stuck: days,
          days_bucket: stuck_days_bucket(days),
          user_uuid: @user&.uuid
        )
      end

      # "Active: Submitted" that has aged past the window without ever being dispensed.
      def submitted_stuck?(rx)
        return false unless rx.refill_status == STATUS_SUBMITTED

        submit_date = parse_stuck_date(rx.refill_submit_date)
        return false unless submit_date
        return false unless days_since(submit_date) > SUBMITTED_STUCK_DAYS

        !dispensed_on_or_after?(rx, submit_date)
      end

      def submitted_stuck_days(rx)
        days_since(parse_stuck_date(rx.refill_submit_date))
      end

      # "Active: Refill in Process" that has aged past the window since the refill was
      # requested. Anchored on the refill-request date (not the previous dispense) so a
      # routine refill cadence is not miscounted as stuck. VistA counts mail/CMOP fills
      # only (window pickups never get tracking); OH is counted but tagged separately (no
      # CMOP signal available yet).
      def refill_in_process_stuck?(rx)
        return false unless rx.refill_status == STATUS_REFILL_IN_PROCESS
        # A future expected fill date (VistA projected refill_date) means scheduled, not stuck.
        return false if refill_scheduled_for_future?(rx)

        anchor_date = refill_in_process_anchor_date(rx)
        return false unless anchor_date && days_since(anchor_date) > REFILL_IN_PROCESS_STUCK_DAYS

        return mail_fill?(rx) if vista_source?(rx)

        true
      end

      def refill_in_process_stuck_days(rx)
        days_since(refill_in_process_anchor_date(rx))
      end

      # Best available "refill requested" anchor for how long an in-process refill has waited.
      # Prefers the per-fill refill record date (mirrors
      # PrescriptionsAdapter#most_recent_rf_submit_date, the date its CMOP in-process bridge
      # uses), then the aggregate submit date. Falls back to the last dispense date only when no
      # submit date exists (e.g. Oracle Health drops refill_submit_date after its 3-day in-flight
      # window) so that source still emits, tagged separately.
      def refill_in_process_anchor_date(rx)
        refill_record_submit_date(rx) ||
          parse_stuck_date(rx.refill_submit_date) ||
          parse_stuck_date(stuck_dispensed_date(rx))
      end

      def dispensed_on_or_after?(rx, submit_date)
        dispensed_date = parse_stuck_date(stuck_dispensed_date(rx))
        dispensed_date.present? && dispensed_date >= submit_date
      end

      # A CMOP/mail fill carries CMOP identifiers; an in-person counter pickup does not.
      def mail_fill?(rx)
        rx.cmop_ndc_number.present? || rx.cmop_division_phone.present?
      end

      def vista_source?(rx)
        rx.source_ehr == UnifiedHealthData::Prescription::SOURCE_EHR_VISTA
      end

      def stuck_source_tag(rx)
        rx.source_ehr.presence || 'unknown'
      end
    end
  end
end
