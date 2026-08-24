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
        else '30+'
        end
      end
    end
  end
end
