# frozen_string_literal: true

require 'digest'

module UnifiedHealthData
  module Adapters
    # PII/PHI-safe formatting and math helpers extracted from
    # OracleHealthRefillWindowLoggingHelper to keep that measurement mixin focused
    # on event decisioning. All methods here are pure with respect to classification.
    #
    # Depends on methods provided by the including adapter / its other mixins:
    # - parse_date_or_epoch (DateTimeHelpers)
    module OracleHealthRefillWindowLoggingFormatters
      def task_meta_value(task, url)
        (task.dig('meta', 'extension') || []).find { |e| e['url'] == url }&.dig('valueString')
      end

      # One-way SHA256 hash of the raw prescription id. Never log the raw id.
      def rx_id_hash(id)
        return nil if id.blank?

        Digest::SHA256.hexdigest(id.to_s)
      end

      # Last-4 suffix of the prescription id for human triage. Mirrors the existing
      # "rx ending in" privacy convention in PrescriptionsAdapter; never the full id.
      def rx_id_suffix(id)
        return nil if id.blank?

        id.to_s.last(4)
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
