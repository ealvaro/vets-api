# frozen_string_literal: true

require 'medical_records/medical_records_log'

module UnifiedHealthData
  module Concerns
    # Logging and metrics for imaging studies. Follows ClinicalNotesLogging pattern.
    # See MedicalRecords::MedicalRecordsLog "Adding a New Domain" guide.
    #
    # Stub Flipper in tests (never use Flipper.enable/disable):
    #   allow(Flipper).to receive(:enabled?).with(:mhv_medical_records_imaging_diagnostic, user).and_return(true)
    module ImagingLogging # rubocop:disable Metrics/ModuleLength
      extend ActiveSupport::Concern

      IMAGING = MedicalRecords::MedicalRecordsLog::IMAGING

      private

      def mr_log
        @mr_log ||= MedicalRecords::MedicalRecordsLog.new(user: @user)
      end

      def imaging_logging_enabled?
        mr_log.diagnostic_enabled?(IMAGING)
      end

      def imaging_statsd_prefix
        "#{self.class::STATSD_KEY_PREFIX}.imaging"
      end

      # Extracts the source-system tag (e.g. 'vista', 'oracle-health') from a raw FHIR resource.
      def extract_source_system(resource)
        tags = resource.dig('meta', 'tag') || []
        source_tag = tags.find { |t| t['system'] == 'http://va.gov/mhv/fhir/tag/source-system' }
        source_tag&.dig('code') || 'unknown'
      end

      # Builds a hash of resource ID → source system from raw SCDF entries.
      def build_source_lookup(raw_records)
        raw_records.each_with_object({}) do |r, lookup|
          resource = r['resource'] || r
          next unless resource['resourceType'] == 'ImagingStudy'

          lookup[resource['id']] = extract_source_system(resource)
        end
      end

      # Tallies source counts and event_id presence by source for raw FHIR entries.
      def tally_raw_entries(imaging_entries)
        source_counts = Hash.new(0)
        event_id_by_source = Hash.new(0)

        imaging_entries.each do |r|
          resource = r['resource']
          source = extract_source_system(resource)
          source_counts[source] += 1
          event_id_by_source[source] += 1 if resource.dig('reasonReference', 0, 'reference').present?
        end

        { source_counts:, event_id_by_source:,
          with_event_id: event_id_by_source.values.sum }
      end

      # Tallies source counts, event_id presence by source, and unique normalized
      # study names for parsed studies.
      def tally_parsed_studies(parsed_studies, source_by_id)
        source_counts = Hash.new(0)
        event_id_by_source = Hash.new(0)
        with_event_id = 0
        normalized_names = []

        parsed_studies.each do |study|
          source = source_by_id[study.id] || 'unknown'
          source_counts[source] += 1
          if study.event_id.present?
            with_event_id += 1
            event_id_by_source[source] += 1
          end
          normalized = normalize_study_name(study.description)
          normalized_names << normalized if normalized
        end

        { source_counts:, event_id_by_source:, with_event_id:,
          unique_name_count: normalized_names.uniq.size,
          named_count: normalized_names.size }
      end

      # Diagnostic: logs counts from the raw SCDF response before adapter parsing.
      # Tracks how many raw ImagingStudy entries have a reasonReference (event_id source),
      # broken down by source system (vista vs oracle-health).
      def log_imaging_raw_entry_metrics(records)
        return unless imaging_logging_enabled?

        imaging_entries = records.select { |r| r.dig('resource', 'resourceType') == 'ImagingStudy' }
        tally = tally_raw_entries(imaging_entries)

        mr_log.diagnostic(
          resource: IMAGING, action: 'index',
          stage: 'raw_from_scdf',
          total_imaging_entries: imaging_entries.size,
          with_event_id: tally[:with_event_id],
          without_event_id: imaging_entries.size - tally[:with_event_id],
          vista_total: tally[:source_counts]['vista'],
          vista_with_event_id: tally[:event_id_by_source]['vista'],
          oh_total: tally[:source_counts]['oracle-health'],
          oh_with_event_id: tally[:event_id_by_source]['oracle-health']
        )
      end

      # Diagnostic: logs counts from parsed ImagingStudy objects that will be sent to the frontend.
      # Tracks how many parsed studies have event_id populated, broken down by source system.
      # Source is correlated from the raw records by matching resource ID.
      def log_imaging_parsed_metrics(parsed_studies, raw_records)
        return unless imaging_logging_enabled?

        source_by_id = build_source_lookup(raw_records)
        tally = tally_parsed_studies(parsed_studies, source_by_id)
        total = parsed_studies.size

        mr_log.diagnostic(
          resource: IMAGING, action: 'index',
          stage: 'parsed',
          total_parsed: total,
          with_event_id: tally[:with_event_id],
          without_event_id: total - tally[:with_event_id],
          vista_total: tally[:source_counts]['vista'],
          vista_with_event_id: tally[:event_id_by_source]['vista'],
          oh_total: tally[:source_counts]['oracle-health'],
          oh_with_event_id: tally[:event_id_by_source]['oracle-health'],
          unique_study_name_count: tally[:unique_name_count],
          duplicate_study_names: tally[:unique_name_count] < tally[:named_count]
        )

        emit_parsed_statsd_metrics(total, tally)
      end

      def emit_parsed_statsd_metrics(total, tally)
        StatsD.gauge("#{imaging_statsd_prefix}.index.total", total)
        StatsD.gauge("#{imaging_statsd_prefix}.index.with_event_id", tally[:with_event_id])
        StatsD.gauge("#{imaging_statsd_prefix}.index.without_event_id", total - tally[:with_event_id])
        if tally[:unique_name_count] < tally[:named_count]
          StatsD.increment("#{imaging_statsd_prefix}.index.duplicate_study_names")
        end
      end

      # Normalizes a study description to lowercase alphanumeric characters only.
      def normalize_study_name(name)
        return nil if name.blank?

        name.downcase.gsub(/[^a-z0-9]/, '')
      end

      # Orchestrates index-level metrics for get_imaging_studies.
      def log_imaging_metrics(raw_records, parsed_studies)
        log_imaging_raw_entry_metrics(raw_records)
        log_imaging_parsed_metrics(parsed_studies, raw_records)
      end

      # Structured error log for imaging failures — provides domain context for triage.
      def log_imaging_error(error)
        mr_log.error(
          resource: IMAGING, action: 'index',
          error_class: error.class.name, error_message: error.message
        )
        StatsD.increment("#{imaging_statsd_prefix}.error")
      end
    end
  end
end
