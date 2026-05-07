# frozen_string_literal: true

require 'medical_records/medical_records_log'

module UnifiedHealthData
  module Concerns
    # Logging and metrics methods for clinical notes operations.
    #
    # This concern is the canonical example of the MedicalRecordsLog pattern.
    # Use it as a template when adding logging for a new domain (allergies, vitals, etc.).
    # See MedicalRecords::MedicalRecordsLog class docs for the full "Adding a New Domain" guide.
    #
    # == Pattern
    #
    # 1. Memoize an MedicalRecordsLog instance via +mr_log+ (receives +@user+ from the host class).
    # 2. Use +mr_log.diagnostic+ for toggle-gated verbose data, +mr_log.info/warn/error+ for always-on.
    # 3. Guard expensive pre-computation with +return unless clinical_notes_logging_enabled?+.
    # 4. Keep StatsD instrumentation alongside log calls for DataDog dashboards.
    #
    # == Specs
    #
    # Stub Flipper (never use Flipper.enable/disable in tests):
    #   allow(Flipper).to receive(:enabled?).with(:mhv_medical_records_clinical_notes_diagnostic, user).and_return(true)
    module ClinicalNotesLogging # rubocop:disable Metrics/ModuleLength
      extend ActiveSupport::Concern

      private

      def mr_log
        @mr_log ||= MedicalRecords::MedicalRecordsLog.new(user: @user)
      end

      def clinical_notes_logging_enabled?
        mr_log.diagnostic_enabled?(MedicalRecords::MedicalRecordsLog::CLINICAL_NOTES)
      end

      def log_loinc_code_distribution(records, record_type = 'Clinical Notes')
        return unless clinical_notes_logging_enabled?

        loinc_code_counts = Hash.new(0)

        records.each do |record|
          loinc_codes = record.loinc_codes
          loinc_codes.each { |code| loinc_code_counts[code] += 1 if code.present? }
        end

        return if loinc_code_counts.empty?

        sorted_code_counts = loinc_code_counts.sort_by { |_, count| -count }
        code_count_pairs = sorted_code_counts.map { |code, count| "#{code}:#{count}" }

        mr_log.diagnostic(
          resource: MedicalRecords::MedicalRecordsLog::CLINICAL_NOTES,
          action: 'loinc_distribution',
          record_type:,
          loinc_code_distribution: code_count_pairs.join(','),
          total_codes: sorted_code_counts.size,
          total_records: records.size
        )
      end

      def log_notes_response_count(total, returned)
        mr_log.diagnostic(
          resource: MedicalRecords::MedicalRecordsLog::CLINICAL_NOTES,
          action: 'filter',
          total_doc_refs: total,
          returned:,
          filtered: total - returned
        )
      end

      # Diagnostic: logs raw entry counts per source from SCDF before any filtering.
      # Helps distinguish "SCDF returned nothing" from "our filters dropped everything".
      def log_raw_source_counts(body)
        return unless clinical_notes_logging_enabled?

        vista_count = body.dig(SourceConstants::VISTA, 'entry')&.size || 0
        oh_count = body.dig(SourceConstants::ORACLE_HEALTH, 'entry')&.size || 0

        mr_log.diagnostic(
          resource: MedicalRecords::MedicalRecordsLog::CLINICAL_NOTES,
          action: 'index',
          stage: 'raw_from_scdf',
          vista_entry_count: vista_count,
          oracle_health_entry_count: oh_count,
          total_entry_count: vista_count + oh_count
        )
      end

      # Proactive: warns when more than half of DocumentReferences are dropped during
      # parsing and date filtering, indicating a possible upstream data-quality regression.
      HIGH_FILTER_RATE_THRESHOLD = 0.5

      def warn_high_filter_rate(doc_ref_count, returned_count, source_breakdown: {})
        return if doc_ref_count.zero?

        filter_rate = 1.0 - (returned_count.to_f / doc_ref_count)
        return unless filter_rate > HIGH_FILTER_RATE_THRESHOLD

        mr_log.warn(
          resource: MedicalRecords::MedicalRecordsLog::CLINICAL_NOTES,
          action: 'index',
          anomaly: 'high_filter_rate',
          filter_rate: (filter_rate * 100).round(1),
          doc_ref_count:,
          returned_count:,
          **source_breakdown
        )

        StatsD.increment("#{self.class::STATSD_KEY_PREFIX}.clinical_notes.anomaly.high_filter_rate")
      end

      # Proactive: warns when multiple notes in a single request have unparseable dates,
      # indicating a possible upstream date-format change.
      DATE_PARSE_FAILURE_THRESHOLD = 3

      def warn_date_parse_failures(failure_count, total_count, source_breakdown: {})
        return unless failure_count >= DATE_PARSE_FAILURE_THRESHOLD

        mr_log.warn(
          resource: MedicalRecords::MedicalRecordsLog::CLINICAL_NOTES,
          action: 'filter',
          anomaly: 'elevated_date_parse_failures',
          failure_count:,
          total_count:,
          **source_breakdown
        )

        StatsD.increment("#{self.class::STATSD_KEY_PREFIX}.clinical_notes.anomaly.date_parse_failures")
      end

      def log_care_summaries_metrics(doc_ref_records, parsed_notes, start_date, end_date)
        clinical_notes_logging_enabled? && log_notes_response_count(doc_ref_records.size, parsed_notes.size)
        clinical_notes_logging_enabled? && log_notes_index_metrics(parsed_notes, start_date, end_date)

        doc_ref_tally = doc_ref_records.map { |r| r['source'] }.tally
        returned_tally = parsed_notes.map(&:source).tally
        source_breakdown = {
          vista_doc_refs: doc_ref_tally[SourceConstants::VISTA] || 0,
          oh_doc_refs: doc_ref_tally[SourceConstants::ORACLE_HEALTH] || 0,
          vista_returned: returned_tally[SourceConstants::VISTA] || 0,
          oh_returned: returned_tally[SourceConstants::ORACLE_HEALTH] || 0
        }
        warn_high_filter_rate(doc_ref_records.size, parsed_notes.size, source_breakdown:)
      end

      # Diagnostic: logs each individual note excluded by the date-range filter.
      # Toggle-gated to avoid log volume in normal operation.
      def log_note_excluded_by_date(note, reason:)
        return unless clinical_notes_logging_enabled?

        mr_log.diagnostic(
          resource: MedicalRecords::MedicalRecordsLog::CLINICAL_NOTES,
          action: 'filter',
          stage: 'date_range_exclusion',
          reason:,
          record_id: note&.id,
          note_date: note&.date,
          note_type: note&.note_type,
          source: note&.source
        )

        StatsD.increment(
          "#{self.class::STATSD_KEY_PREFIX}.clinical_notes.filter.date_range_exclusion",
          tags: ["reason:#{reason}", "source:#{note&.source || 'unknown'}"]
        )
      end

      def log_notes_index_metrics(parsed_notes, start_date, end_date)
        total_notes = parsed_notes.size
        vista_count = parsed_notes.count { |n| n.source == SourceConstants::VISTA }
        oracle_health_count = parsed_notes.count { |n| n.source == SourceConstants::ORACLE_HEALTH }

        mr_log.diagnostic(
          resource: MedicalRecords::MedicalRecordsLog::CLINICAL_NOTES,
          action: 'index',
          total_notes:,
          vista_count:,
          oracle_health_count:,
          start_date:,
          end_date:
        )

        StatsD.gauge("#{self.class::STATSD_KEY_PREFIX}.clinical_notes.index.total", total_notes)
        StatsD.gauge("#{self.class::STATSD_KEY_PREFIX}.clinical_notes.index.vista", vista_count)
        StatsD.gauge("#{self.class::STATSD_KEY_PREFIX}.clinical_notes.index.oracle_health", oracle_health_count)
      end

      def log_notes_show_metrics(source, result)
        source_used = source || 'source not specified'

        mr_log.diagnostic(
          resource: MedicalRecords::MedicalRecordsLog::CLINICAL_NOTES,
          action: 'show',
          source: source_used,
          note_found: result.present?,
          note_type: result&.note_type
        )

        StatsD.increment("#{self.class::STATSD_KEY_PREFIX}.clinical_notes.show.source", tags: ["source:#{source_used}"])

        # Proactive: always-on warning when a note ID from the index can't be fetched individually.
        # This is visible in Splunk without needing the diagnostic toggle.
        if result.blank?
          mr_log.warn(
            resource: MedicalRecords::MedicalRecordsLog::CLINICAL_NOTES,
            action: 'show',
            anomaly: 'note_not_found',
            source: source_used
          )
          StatsD.increment("#{self.class::STATSD_KEY_PREFIX}.clinical_notes.show.not_found")
        end
      end
    end
  end
end
