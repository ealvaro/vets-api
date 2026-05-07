# frozen_string_literal: true

require 'medical_records/medical_records_log'

module UnifiedHealthData
  module Concerns
    # Logging and metrics for labs and tests. Follows ClinicalNotesLogging pattern.
    # See MedicalRecords::MedicalRecordsLog "Adding a New Domain" guide.
    #
    # Stub Flipper in tests (never use Flipper.enable/disable):
    #   allow(Flipper).to receive(:enabled?).with(:mhv_medical_records_labs_and_tests_diagnostic, user).and_return(true)
    module LabsAndTestsLogging # rubocop:disable Metrics/ModuleLength
      extend ActiveSupport::Concern

      LABS = MedicalRecords::MedicalRecordsLog::LABS_AND_TESTS
      HIGH_FILTER_RATE_THRESHOLD = 0.5
      MISSING_DATE_THRESHOLD = 3
      EMPTY_OBSERVATIONS_THRESHOLD = 3

      private

      def mr_log
        @mr_log ||= MedicalRecords::MedicalRecordsLog.new(user: @user)
      end

      def labs_logging_enabled?
        mr_log.diagnostic_enabled?(LABS)
      end

      def labs_statsd_prefix
        "#{self.class::STATSD_KEY_PREFIX}.labs_and_tests"
      end

      # StatsD tags array including caller when present.
      def labs_statsd_tags
        @labs_caller ? ["caller:#{@labs_caller}"] : []
      end

      # Base metadata included in every structured log entry.
      def labs_caller_metadata
        @labs_caller ? { caller: @labs_caller } : {}
      end

      # Dual-path logging: structured mr_log when available, Rails.logger fallback otherwise.
      def log_adapter(level, structured_opts, fallback_message, fallback_opts = {})
        if @mr_log
          @mr_log.public_send(level, **structured_opts)
        else
          Rails.logger.public_send(level, fallback_message, fallback_opts.presence)
        end
      end

      def log_warnings(record, encoded_data, observations)
        log_final_status_warning(record, record['resource']['status'], encoded_data, observations)
        log_missing_date_warning(record)
      end

      def log_filtered_diagnostic_report(record, reason)
        resource = record['resource']
        log_adapter(
          :info,
          { resource: LABS, action: 'filter', report_id: resource['id'],
            status: resource['status'], reason:, filtering: true },
          "Filtered DiagnosticReport: id=#{resource['id']}, status=#{resource['status']}, reason=#{reason}",
          { service: 'unified_health_data', filtering: true }
        )
        StatsD.increment('unified_health_data.lab_or_test.filtered_diagnostic_report',
                         tags: ["reason:#{reason}"])
      end

      def log_filtered_observations(record, filtered_count, total_count)
        resource = record['resource']
        log_adapter(
          :info,
          { resource: LABS, action: 'filter_observations', report_id: resource['id'],
            filtered: filtered_count, total: total_count, filtering: true },
          "Filtered #{filtered_count}/#{total_count} Observations from DiagnosticReport #{resource['id']}",
          { service: 'unified_health_data', filtering: true }
        )
        # Increment the counter once per DiagnosticReport that has filtered observations
        StatsD.increment('unified_health_data.lab_or_test.filtered_observations')
      end

      # Logs when an individual record fails to parse. Isolates one bad record from
      # killing the entire batch so the veteran still sees the rest of their results.
      def log_record_parse_failure(record, error)
        report_id = record.dig('resource', 'id')
        log_adapter(
          :error,
          { resource: LABS, action: 'parse', anomaly: 'record_parse_failure',
            report_id:, error_class: error.class.name, error_message: error.message },
          "Failed to parse DiagnosticReport #{report_id}: #{error.class} - #{error.message}",
          { service: 'unified_health_data' }
        )
        StatsD.increment('unified_health_data.lab_or_test.parse_failure')
      end

      # Logs when an individual observation within a DiagnosticReport fails to parse.
      # Isolates one bad observation so the rest of the record's observations are still returned.
      def log_observation_parse_failure(record, obs, error)
        report_id = record.dig('resource', 'id')
        observation_id = obs['id']
        log_adapter(
          :error,
          { resource: LABS, action: 'parse', anomaly: 'observation_parse_failure',
            report_id:, observation_id:, error_class: error.class.name, error_message: error.message },
          "Failed to parse Observation #{observation_id} in DiagnosticReport #{report_id}: " \
          "#{error.class} - #{error.message}",
          { service: 'unified_health_data' }
        )
        StatsD.increment('unified_health_data.lab_or_test.observation_parse_failure')
      end

      def log_final_status_warning(record, status, encoded_data, observations)
        return unless status == 'final' && encoded_data.blank? && observations.blank?

        report_id = record['resource']['id']
        if @mr_log
          @mr_log.warn(resource: LABS, action: 'parse', anomaly: 'final_status_empty_data', report_id:)
        else
          patient_ref = record['resource']&.dig('subject', 'reference')
          patient_last_four = patient_ref&.split('/')&.last&.last(4) || 'unknown'
          Rails.logger.warn(
            "DiagnosticReport #{report_id} has status 'final' but is missing " \
            "both encoded data and observations (Patient: #{patient_last_four})",
            { service: 'unified_health_data' }
          )
        end
        StatsD.increment('unified_health_data.lab_or_test.final_status_empty_data')
      end

      def log_missing_date_warning(record)
        resource = record['resource']
        effective_date_time = resource['effectiveDateTime']
        effective_period = resource['effectivePeriod']

        detail = if effective_date_time.blank? && effective_period.blank?
                   'missing effectiveDateTime and effectivePeriod'
                 elsif effective_period.present? && effective_period['start'].blank?
                   'missing effectivePeriod.start'
                 end
        return unless detail

        log_adapter(
          :warn,
          { resource: LABS, action: 'parse', anomaly: 'missing_date', report_id: resource['id'], detail: },
          "DiagnosticReport #{resource['id']} is #{detail}",
          { service: 'unified_health_data' }
        )
      end

      # Logs test code and display name distribution (migrated from Logging class).
      # NOTE: warn_short_test_names is intentionally diagnostic-gated (unlike the
      # always-on anomaly warnings in log_labs_metrics) because short names (≤3 chars)
      # may reflect standard lab abbreviations (e.g. "BUN", "K", "Na") rather than
      # data quality defects. Once Datadog data confirms whether firing is actionable,
      # this can be promoted to always-on in log_labs_metrics.
      def log_test_code_distribution(records)
        return unless labs_logging_enabled?

        code_counts, name_counts, short_name_count = count_test_codes(records)
        return if code_counts.empty? && name_counts.empty?

        emit_distribution_diagnostic(code_counts, name_counts, records.size)
        warn_short_test_names(short_name_count, records.size)
      end

      def count_test_codes(records)
        code_counts = Hash.new(0)
        name_counts = Hash.new(0)
        short_name_count = 0
        records.each do |record|
          code_counts[record.test_code] += 1 if record.test_code.present?
          if record.display.present?
            name_counts[record.display] += 1
            short_name_count += 1 if record.display.length <= 3
          end
        end
        [code_counts, name_counts, short_name_count]
      end

      def emit_distribution_diagnostic(code_counts, name_counts, total_records)
        sorted_codes = code_counts.sort_by { |_, c| -c }
        sorted_names = name_counts.sort_by { |_, c| -c }
        mr_log.diagnostic(
          resource: LABS, action: 'test_code_distribution',
          test_code_distribution: sorted_codes.map { |code, c| "#{code}:#{c}" }.join(','),
          test_name_distribution: sorted_names.map { |name, c| "#{name}:#{c}" }.join(','),
          total_codes: sorted_codes.size, total_names: sorted_names.size, total_records:,
          **labs_caller_metadata
        )
        StatsD.gauge("#{labs_statsd_prefix}.diagnostic.test_code_count", sorted_codes.size, tags: labs_statsd_tags)
      end

      def log_labs_response_count(raw_count, parsed_count)
        mr_log.diagnostic(
          resource: LABS, action: 'filter',
          total_entries: raw_count, returned: parsed_count, filtered: raw_count - parsed_count,
          **labs_caller_metadata
        )
      end

      def log_labs_index_metrics(parsed_labs, start_date, end_date)
        total = parsed_labs.size
        vista_count = parsed_labs.count { |l| l.source == SourceConstants::VISTA }
        oh_count = parsed_labs.count { |l| l.source == SourceConstants::ORACLE_HEALTH }
        total_obs = parsed_labs.sum { |l| l.observations.size }
        mr_log.diagnostic(
          resource: LABS, action: 'index', total_labs: total, vista_count:,
          oracle_health_count: oh_count, total_observations: total_obs,
          avg_observations_per_report: total.positive? ? (total_obs.to_f / total).round(1) : 0,
          start_date:, end_date:, **labs_caller_metadata
        )
        StatsD.gauge("#{labs_statsd_prefix}.index.total", total, tags: labs_statsd_tags)
        StatsD.gauge("#{labs_statsd_prefix}.index.vista", vista_count, tags: labs_statsd_tags)
        StatsD.gauge("#{labs_statsd_prefix}.index.oracle_health", oh_count, tags: labs_statsd_tags)
      end

      # Shared helper for always-on anomaly warnings: logs + increments StatsD.
      def emit_anomaly(action:, anomaly:, **metadata)
        mr_log.warn(resource: LABS, action:, anomaly:, **metadata, **labs_caller_metadata)
        StatsD.increment("#{labs_statsd_prefix}.anomaly.#{anomaly}", tags: labs_statsd_tags)
      end

      # Warns when >50% of DiagnosticReports are dropped during parsing.
      def warn_labs_high_filter_rate(raw_count, parsed_count)
        return if raw_count.zero?

        filter_rate = 1.0 - (parsed_count.to_f / raw_count)
        return unless filter_rate > HIGH_FILTER_RATE_THRESHOLD

        emit_anomaly(action: 'index', anomaly: 'high_filter_rate',
                     filter_rate: (filter_rate * 100).round(1), raw_count:, parsed_count:)
      end

      def warn_missing_dates(missing_date_count, total_count)
        return unless missing_date_count >= MISSING_DATE_THRESHOLD

        emit_anomaly(action: 'parse', anomaly: 'elevated_missing_dates',
                     missing_count: missing_date_count, total_count:)
      end

      def warn_empty_observations(empty_count, total_count)
        return unless empty_count >= EMPTY_OBSERVATIONS_THRESHOLD

        emit_anomaly(action: 'parse', anomaly: 'elevated_empty_observations',
                     empty_count:, total_count:)
      end

      # Replaces PersonalInformationLog approach — no PII stored.
      def warn_short_test_names(short_name_count, total_count)
        return if short_name_count.zero?

        emit_anomaly(action: 'parse', anomaly: 'short_test_names',
                     short_name_count:, total_count:)
      end

      # Structured error log for get_labs failures — provides domain context for triage.
      def log_labs_error(error, start_date, end_date)
        mr_log.error(
          resource: LABS, action: 'index',
          error_class: error.class.name, error_message: error.message,
          start_date:, end_date:, **labs_caller_metadata
        )
        StatsD.increment("#{labs_statsd_prefix}.error", tags: labs_statsd_tags)
      end

      # Orchestrates index-level metrics and proactive warnings for get_labs.
      def log_labs_metrics(combined_records, parsed_labs, start_date, end_date)
        parsed_count = parsed_labs.size
        raw_count = combined_records.size

        labs_logging_enabled? && log_labs_response_count(raw_count, parsed_count)
        labs_logging_enabled? && log_labs_index_metrics(parsed_labs, start_date, end_date)
        warn_labs_high_filter_rate(raw_count, parsed_count)
        warn_missing_dates(parsed_labs.count { |l| l.date_completed.blank? }, parsed_count)
        warn_empty_observations(parsed_labs.count { |l| l.observations.empty? }, parsed_count)
      end
    end
  end
end
