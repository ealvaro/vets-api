# frozen_string_literal: true

require 'medical_records/medical_records_log'

module UnifiedHealthData
  module Concerns
    # Logging and metrics for allergies. Follows ClinicalNotesLogging pattern.
    # See MedicalRecords::MedicalRecordsLog "Adding a New Domain" guide.
    #
    # Stub Flipper in tests (never use Flipper.enable/disable):
    #   allow(Flipper).to receive(:enabled?).with(:mhv_medical_records_allergies_diagnostic, user).and_return(true)
    module AllergiesLogging
      extend ActiveSupport::Concern

      ALLERGIES = MedicalRecords::MedicalRecordsLog::ALLERGIES
      HIGH_FILTER_RATE_THRESHOLD = 0.5

      private

      def mr_log
        @mr_log ||= MedicalRecords::MedicalRecordsLog.new(user: @user)
      end

      def allergies_logging_enabled?
        mr_log.diagnostic_enabled?(ALLERGIES)
      end

      def allergies_statsd_prefix
        "#{self.class::STATSD_KEY_PREFIX}.allergies"
      end

      def log_allergies_response_count(raw_count, returned_count)
        mr_log.diagnostic(
          resource: ALLERGIES, action: 'filter',
          total_entries: raw_count, returned: returned_count, filtered: raw_count - returned_count
        )
      end

      def log_allergies_index_metrics(combined_records, returned_count)
        vista_count = combined_records.count { |r| r['source'] == SourceConstants::VISTA }
        oh_count = combined_records.count { |r| r['source'] == SourceConstants::ORACLE_HEALTH }

        mr_log.diagnostic(
          resource: ALLERGIES, action: 'index',
          total_allergies: returned_count, vista_raw: vista_count, oracle_health_raw: oh_count
        )

        StatsD.gauge("#{allergies_statsd_prefix}.index.total", returned_count)
        StatsD.gauge("#{allergies_statsd_prefix}.index.vista", vista_count)
        StatsD.gauge("#{allergies_statsd_prefix}.index.oracle_health", oh_count)
      end

      # Always-on: warns when more than half of allergy records are dropped during parsing.
      def warn_allergies_high_filter_rate(raw_count, returned_count, source_breakdown: {})
        return if raw_count.zero?

        filter_rate = 1.0 - (returned_count.to_f / raw_count)
        return unless filter_rate > HIGH_FILTER_RATE_THRESHOLD

        mr_log.warn(
          resource: ALLERGIES, action: 'index',
          anomaly: 'high_filter_rate',
          filter_rate: (filter_rate * 100).round(1),
          raw_count:, returned_count:,
          **source_breakdown
        )

        StatsD.increment("#{allergies_statsd_prefix}.anomaly.high_filter_rate")
      end

      # Always-on: warns when parsed allergies contain duplicate IDs.
      def warn_allergies_duplicate_ids(parsed_allergies)
        ids = parsed_allergies.map(&:id)
        duplicate_ids = ids.tally.select { |_id, count| count > 1 }
        return if duplicate_ids.empty?

        mr_log.warn(
          resource: ALLERGIES, action: 'index',
          anomaly: 'duplicate_ids',
          duplicate_ids: duplicate_ids.keys,
          duplicate_count: duplicate_ids.values.sum,
          total_count: parsed_allergies.size
        )

        StatsD.increment("#{allergies_statsd_prefix}.anomaly.duplicate_ids")
      end

      # Diagnostic: logs raw entry counts per source from SCDF before any filtering.
      # Helps distinguish "SCDF returned nothing" from "our filters dropped everything".
      def log_allergies_raw_source_counts(body)
        return unless allergies_logging_enabled?

        vista_count = body.dig(SourceConstants::VISTA, 'entry')&.size || 0
        oh_count = body.dig(SourceConstants::ORACLE_HEALTH, 'entry')&.size || 0

        mr_log.diagnostic(
          resource: ALLERGIES, action: 'index',
          stage: 'raw_from_scdf',
          vista_entry_count: vista_count,
          oracle_health_entry_count: oh_count,
          total_entry_count: vista_count + oh_count
        )
      end

      # Structured error log for get_allergies failures — provides domain context for triage.
      def log_allergies_error(error)
        mr_log.error(
          resource: ALLERGIES, action: 'index',
          error_class: error.class.name, error_message: error.message
        )
        StatsD.increment("#{allergies_statsd_prefix}.error")
      end

      # Orchestrates index-level metrics and proactive warnings for get_allergies.
      def log_allergies_metrics(combined_records, parsed_allergies)
        raw_count = combined_records.size
        returned_count = parsed_allergies.size

        vista_raw = combined_records.count { |r| r['source'] == SourceConstants::VISTA }
        oh_raw = combined_records.count { |r| r['source'] == SourceConstants::ORACLE_HEALTH }
        source_breakdown = { vista_raw:, oracle_health_raw: oh_raw }

        allergies_logging_enabled? && log_allergies_response_count(raw_count, returned_count)
        allergies_logging_enabled? && log_allergies_index_metrics(combined_records, returned_count)
        warn_allergies_high_filter_rate(raw_count, returned_count, source_breakdown:)
        warn_allergies_duplicate_ids(parsed_allergies)
      end
    end
  end
end
