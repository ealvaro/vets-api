# frozen_string_literal: true

require 'digest'

module UnifiedHealthData
  module Concerns
    # PII/PHI-safe date/format helpers extracted from PrescriptionStuckStatusLogging
    # to keep that measurement mixin focused on stuck-status decisioning.
    module PrescriptionStuckStatusFormatters
      # One-way SHA256 hash of the raw prescription id. Never log the raw id.
      def stuck_rx_id_hash(id)
        return nil if id.blank?

        Digest::SHA256.hexdigest(id.to_s)
      end

      def parse_stuck_date(value)
        return nil if value.blank?

        Date.parse(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end

      # Most recent per-fill refill-request date (mirrors
      # PrescriptionsAdapter#most_recent_rf_submit_date), or nil when no record carries one.
      def refill_record_submit_date(rx)
        Array(rx.dispenses).filter_map do |d|
          parse_stuck_date(d[:refill_submit_date]) if d.is_a?(Hash)
        end.max
      end

      def stuck_dispensed_date(rx)
        rx.sorted_dispensed_date.presence || rx.dispensed_date
      end

      # True when the expected fill date is still in the future. For a refill in process,
      # refill_date is VistA's *projected* next-available date, so a future value means the
      # refill is on schedule, not stuck. (Oracle Health's refill_date is a past dispense
      # date or nil, so this is a natural no-op there.)
      def refill_scheduled_for_future?(rx)
        expected_fill = parse_stuck_date(rx.refill_date)
        expected_fill.present? && expected_fill > Time.current.to_date
      end

      # Whole days elapsed, computed the same way as the OH adapter's
      # OracleHealthRefillWindowLoggingFormatters#days_between (floor of elapsed time
      # over one day) so both producers of the stuck metrics agree.
      def days_since(date)
        return nil if date.nil?

        ((Time.current - date.in_time_zone) / 1.day).floor
      end

      # Low-cardinality bucket for StatsD tagging.
      def stuck_days_bucket(days)
        return 'unknown' if days.nil?

        case days
        when ..3 then '0-3'
        when 4..7 then '4-7'
        when 8..14 then '8-14'
        when 15..30 then '15-30'
        else '30_plus'
        end
      end
    end
  end
end
