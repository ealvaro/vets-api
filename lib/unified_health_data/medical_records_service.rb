# frozen_string_literal: true

require_relative 'base_service'
require_relative 'adapters/allergy_adapter'
require_relative 'adapters/clinical_notes_adapter'
require_relative 'adapters/immunization_adapter'
require_relative 'adapters/conditions_adapter'
require_relative 'adapters/lab_or_test_adapter'
require_relative 'adapters/vital_adapter'
require_relative 'reference_range_formatter'
require_relative 'concerns/clinical_notes_logging'
require_relative 'concerns/labs_and_tests_logging'
require_relative 'concerns/vaccines_logging'
require_relative 'concerns/allergies_logging'
require_relative 'concerns/conditions_logging'
require_relative 'concerns/vitals_logging'
require_relative 'concerns/facility_cache_warming'

module UnifiedHealthData
  class MedicalRecordsService < UnifiedHealthData::BaseService
    include Concerns::ClinicalNotesLogging
    include Concerns::LabsAndTestsLogging
    include Concerns::VaccinesLogging
    include Concerns::AllergiesLogging
    include Concerns::ConditionsLogging
    include Concerns::VitalsLogging
    include Concerns::FacilityCacheWarming

    def get_labs(start_date:, end_date:, caller: nil, no_cache: false)
      validate_icn!
      @labs_caller = caller
      start_date, end_date = normalize_date_range(start_date, end_date)
      with_monitoring do
        response = uhd_client.get_labs_by_date(patient_id: @user.icn, start_date:, end_date:, no_cache:)
        body = response.body
        warnings = extract_warnings(body)

        combined_records = fetch_combined_records(body)

        # Pre-warm facility cache to avoid N+1 API calls during parsing
        # Each unique station number is fetched once and cached for 12 hours
        prewarm_facility_cache(combined_records)

        parsed_records = lab_or_test_adapter.parse_labs(combined_records)

        log_test_code_distribution(parsed_records)
        log_labs_metrics(combined_records, parsed_records, start_date, end_date)

        { records: parsed_records, warnings: }
      rescue Common::Exceptions::BackendServiceException,
             Common::Client::Errors::ClientError,
             Faraday::Error => e
        log_labs_error(e, start_date, end_date)
        raise
      end
    end

    def get_conditions(no_cache: false)
      validate_icn!
      with_monitoring do
        start_date = default_start_date
        end_date = default_end_date

        response = uhd_client.get_conditions_by_date(patient_id: @user.icn, start_date:, end_date:, no_cache:)
        body = response.body
        warnings = extract_warnings(body)

        log_conditions_raw_source_counts(body)
        combined_records = fetch_combined_records(body)
        parsed_conditions = conditions_adapter.parse(combined_records)
        log_conditions_metrics(combined_records, parsed_conditions)
        { records: parsed_conditions, warnings: }
      rescue Common::Exceptions::BackendServiceException,
             Common::Client::Errors::ClientError,
             Faraday::Error => e
        log_conditions_error(e)
        raise
      end
    end

    def get_single_condition(condition_id)
      validate_icn!
      with_monitoring do
        start_date = default_start_date
        end_date = default_end_date

        response = uhd_client.get_conditions_by_date(patient_id: @user.icn, start_date:, end_date:)
        body = response.body

        combined_records = fetch_combined_records(body)
        target_record = combined_records.find { |record| record['resource']['id'] == condition_id }
        return nil unless target_record

        conditions_adapter.parse([target_record]).first
      end
    end

    def get_care_summaries_and_notes(start_date: nil, end_date: nil, no_cache: false)
      validate_icn!
      with_monitoring do
        start_date, end_date = normalize_date_range(start_date, end_date)

        response = uhd_client.get_notes_by_date(patient_id: @user.icn, start_date:, end_date:, no_cache:)
        body = response.body
        warnings = extract_warnings(body)

        remap_vista_uid(body)
        log_raw_source_counts(body)
        combined_records = fetch_combined_records(body)
        doc_ref_records = combined_records.select { |record| record['resource']['resourceType'] == 'DocumentReference' }
        parsed_notes = clinical_notes_adapter.parse(doc_ref_records)

        # Filter by date range on parsed notes (single source of truth for what we return).
        # SCDF may return notes outside the requested range; this ensures only in-range notes are returned.
        parsed_notes = filter_parsed_notes_by_date_range(parsed_notes, start_date, end_date)

        log_loinc_code_distribution(parsed_notes, 'Clinical Notes')
        log_care_summaries_metrics(doc_ref_records, parsed_notes, start_date, end_date)

        { records: parsed_notes, warnings: }
      end
    end

    def get_single_summary_or_note(note_id, source: nil)
      validate_icn!
      with_monitoring do
        result = fetch_oracle_health_note(note_id, source || SourceConstants::ORACLE_HEALTH)
        clinical_notes_logging_enabled? && log_notes_show_metrics(source, result)
        result
      end
    end

    def get_vitals(no_cache: false)
      validate_icn!
      with_monitoring do
        # NOTE: we must pass in a startDate and endDate to SCDF
        start_date = default_start_date
        end_date = default_end_date

        response = uhd_client.get_vitals_by_date(patient_id: @user.icn, start_date:, end_date:, no_cache:)
        body = response.body
        warnings = extract_warnings(body)

        log_vitals_raw_source_counts(body)
        combined_records = fetch_combined_records(body)

        parsed_vitals = vitals_adapter.parse(combined_records)
        log_vitals_metrics(combined_records, parsed_vitals)
        { records: parsed_vitals, warnings: }
      rescue Common::Exceptions::BackendServiceException,
             Common::Client::Errors::ClientError,
             Faraday::Error => e
        log_vitals_error(e)
        raise
      end
    end

    def get_allergies(no_cache: false)
      validate_icn!
      with_monitoring do
        # NOTE: we must pass in a startDate and endDate to SCDF
        start_date = default_start_date
        end_date = default_end_date

        response = uhd_client.get_allergies_by_date(patient_id: @user.icn, start_date:, end_date:, no_cache:)
        body = response.body
        warnings = extract_warnings(body)

        log_allergies_raw_source_counts(body)
        remap_vista_identifier(body)
        combined_records = fetch_combined_records(body)

        parsed_allergies = allergy_adapter.parse(combined_records)
        log_allergies_metrics(combined_records, parsed_allergies)
        { records: parsed_allergies, warnings: }
      rescue Common::Exceptions::BackendServiceException,
             Common::Client::Errors::ClientError,
             Faraday::Error => e
        log_allergies_error(e)
        raise
      end
    end

    def get_single_allergy(allergy_id)
      validate_icn!
      with_monitoring do
        # NOTE: we must pass in a startDate and endDate to SCDF
        start_date = default_start_date
        end_date = default_end_date

        response = uhd_client.get_allergies_by_date(patient_id: @user.icn, start_date:, end_date:)
        body = response.body

        remap_vista_identifier(body)
        combined_records = fetch_combined_records(body)

        filtered = combined_records.find { |record| record['resource']['id'] == allergy_id }
        return nil unless filtered

        allergy_adapter.parse_single_allergy(filtered)
      end
    end

    def get_immunizations(no_cache: false)
      validate_icn!
      with_monitoring do
        # NOTE: we must pass in a startDate and endDate to SCDF
        start_date = default_start_date
        end_date = default_end_date

        response = uhd_client.get_immunizations_by_date(patient_id: @user.icn, start_date:, end_date:, no_cache:)
        body = response.body
        warnings = extract_warnings(body)

        log_vaccines_raw_source_counts(body)
        combined_records = fetch_combined_records(body)

        parsed_immunizations = immunization_adapter.parse(combined_records)
        log_vaccines_metrics(combined_records, parsed_immunizations)
        { records: parsed_immunizations, warnings: }
      rescue Common::Exceptions::BackendServiceException,
             Common::Client::Errors::ClientError,
             Faraday::Error => e
        log_vaccines_error(e)
        raise
      end
    end

    private

    # Keeps only parsed notes whose date falls within [start_date, end_date] (inclusive).
    # Filtering on parsed notes (same objects we return) so the response is guaranteed correct.
    # Tracks date-parse failures and emits an aggregated warning when the count exceeds threshold.
    def filter_parsed_notes_by_date_range(notes, start_date, end_date) # rubocop:disable Metrics/MethodLength
      return notes if notes.blank? || start_date.blank? || end_date.blank?

      start_d = DateTime.parse(start_date.to_s).to_date
      end_d = DateTime.parse(end_date.to_s).to_date
      date_parse_failure_count = 0
      source_failures = Hash.new(0)

      filtered = notes.select do |note|
        if note.blank? || note.date.blank?
          log_note_excluded_by_date(note, reason: 'blank_date')
          next false
        end

        note_date = DateTime.parse(note.date.to_s).to_date
        in_range = note_date >= start_d && note_date <= end_d
        log_note_excluded_by_date(note, reason: 'out_of_range') unless in_range
        in_range
      rescue ArgumentError, TypeError
        date_parse_failure_count += 1
        source_failures[note&.source || 'unknown'] += 1
        log_note_excluded_by_date(note, reason: 'unparseable_date')
        false
      end

      if date_parse_failure_count.positive?
        warn_date_parse_failures(date_parse_failure_count, notes.size, source_breakdown: source_failures)
      end
      filtered
    end

    # Fetches a single Oracle Health note directly via the SCDF source-specific endpoint.
    # The SCDF response is a FHIR Bundle containing Patient, DocumentReference, and
    # OperationOutcome entries. We extract the DocumentReference for parsing.
    def fetch_oracle_health_note(note_id, source)
      response = uhd_client.get_note_by_source(
        patient_id: @user.icn,
        source:,
        record_id: note_id,
        start_date: default_start_date,
        end_date: default_end_date
      )
      body = response.body
      return nil if body.blank?

      doc_ref = extract_bundle(body, 'DocumentReference')
      return nil unless doc_ref

      record = { 'resource' => doc_ref }
      record['source'] = source
      clinical_notes_adapter.parse_single_note(record)
    end

    def allergy_adapter
      @allergy_adapter ||= UnifiedHealthData::Adapters::AllergyAdapter.new(user: @user)
    end

    def lab_or_test_adapter
      @lab_or_test_adapter ||= UnifiedHealthData::Adapters::LabOrTestAdapter.new(mr_log:)
    end

    def clinical_notes_adapter
      @clinical_notes_adapter ||= UnifiedHealthData::Adapters::ClinicalNotesAdapter.new(user: @user)
    end

    def conditions_adapter
      @conditions_adapter ||= UnifiedHealthData::Adapters::ConditionsAdapter.new(user: @user)
    end

    def vitals_adapter
      @vitals_adapter ||= UnifiedHealthData::Adapters::VitalAdapter.new(user: @user)
    end

    def immunization_adapter
      @immunization_adapter ||= UnifiedHealthData::Adapters::ImmunizationAdapter.new(user: @user)
    end
  end
end
