# frozen_string_literal: true

require 'common/client/base'
require 'common/exceptions/not_implemented'
require_relative 'configuration'
require_relative 'models/prescription'
require_relative 'adapters/allergy_adapter'
require_relative 'adapters/clinical_notes_adapter'
require_relative 'adapters/immunization_adapter'
require_relative 'adapters/prescriptions_adapter'
require_relative 'adapters/conditions_adapter'
require_relative 'adapters/lab_or_test_adapter'
require_relative 'adapters/vital_adapter'
require_relative 'adapters/ccd_adapter'
require_relative 'reference_range_formatter'
require_relative 'client'
require_relative 'source_constants'
require_relative 'concerns/clinical_notes_logging'
require_relative 'concerns/labs_and_tests_logging'
require_relative 'concerns/vaccines_logging'
require_relative 'concerns/allergies_logging'
require_relative 'concerns/conditions_logging'
require_relative 'concerns/vitals_logging'
require_relative 'concerns/facility_cache_warming'

module UnifiedHealthData
  class Service # rubocop:disable Metrics/ClassLength
    STATSD_KEY_PREFIX = 'api.uhd'
    include Common::Client::Concerns::Monitoring
    include Concerns::ClinicalNotesLogging
    include Concerns::LabsAndTestsLogging
    include Concerns::VaccinesLogging
    include Concerns::AllergiesLogging
    include Concerns::ConditionsLogging
    include Concerns::VitalsLogging
    include Concerns::FacilityCacheWarming

    def initialize(user)
      super()
      @user = user
    end

    def get_labs(start_date:, end_date:, caller: nil)
      validate_icn!
      @labs_caller = caller
      with_monitoring do
        response = uhd_client.get_labs_by_date(patient_id: @user.icn, start_date:, end_date:)
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

    def get_conditions
      validate_icn!
      with_monitoring do
        start_date = default_start_date
        end_date = default_end_date

        response = uhd_client.get_conditions_by_date(patient_id: @user.icn, start_date:, end_date:)
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

    # Retrieves prescriptions for the current user from unified health data sources
    #
    # @param current_only [Boolean] When true, applies filtering logic to exclude:
    #   - Discontinued/expired medications older than 180 days
    #   Defaults to false to return all prescriptions without filtering
    # @return [Hash] Hash with :prescriptions (Array<UnifiedHealthData::Prescription>) and
    #   :metadata (Hash including :has_failed_stations Boolean)
    def get_prescriptions(current_only: false)
      validate_icn!
      with_monitoring do
        start_date = default_start_date
        end_date = default_end_date
        response = uhd_client.get_prescriptions_by_date(patient_id: @user.icn, start_date:, end_date:)
        body = response.body

        adapter = UnifiedHealthData::Adapters::PrescriptionsAdapter.new(@user)
        result = adapter.parse(body, current_only:)

        Rails.logger.info(
          message: 'UHD prescriptions retrieved',
          total_prescriptions: result[:prescriptions].size,
          current_filtering_applied: current_only,
          service: 'unified_health_data'
        )

        result
      end
    end

    def refill_prescription(orders)
      validate_icn!
      normalized_orders = normalize_orders(orders)
      with_monitoring do
        response = uhd_client.refill_prescription_orders(build_refill_request_body(normalized_orders))
        result = parse_refill_response(response)
        validate_refill_response_count(normalized_orders, result)
        result
      end
    rescue Common::Exceptions::BackendServiceException => e
      raise e if e.original_status && e.original_status >= 500
    rescue => e
      Rails.logger.error("Error submitting prescription refill: #{e.message}")
      build_error_response(normalized_orders)
    end

    def get_care_summaries_and_notes(start_date: nil, end_date: nil)
      validate_icn!
      with_monitoring do
        start_date, end_date = normalize_date_range(start_date, end_date)

        response = uhd_client.get_notes_by_date(patient_id: @user.icn, start_date:, end_date:)
        body = response.body
        warnings = extract_warnings(body)

        remap_vista_uid(body)
        log_raw_source_counts(body)
        combined_records = fetch_combined_records(body)
        doc_ref_records = combined_records.select { |record| record['resource']['resourceType'] == 'DocumentReference' }
        parsed_notes = parse_notes(doc_ref_records)

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

    def get_vitals
      validate_icn!
      with_monitoring do
        # NOTE: we must pass in a startDate and endDate to SCDF
        start_date = default_start_date
        end_date = default_end_date

        response = uhd_client.get_vitals_by_date(patient_id: @user.icn, start_date:, end_date:)
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

    def get_allergies
      validate_icn!
      with_monitoring do
        # NOTE: we must pass in a startDate and endDate to SCDF
        start_date = default_start_date
        end_date = default_end_date

        response = uhd_client.get_allergies_by_date(patient_id: @user.icn, start_date:, end_date:)
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

    def get_immunizations
      validate_icn!
      with_monitoring do
        # NOTE: we must pass in a startDate and endDate to SCDF
        start_date = default_start_date
        end_date = default_end_date

        response = uhd_client.get_immunizations_by_date(patient_id: @user.icn, start_date:, end_date:)
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

    # Use of this is behind va_online_scheduling_uhd_avs_metadata flipper
    def get_all_avs_metadata(start_date:, end_date:) # rubocop:disable Metrics/MethodLength
      validate_icn!
      with_monitoring do
        response = uhd_client.get_all_avs(patient_id: @user.icn, start_date:, end_date:)
        # SCDF returns a bundle: DocumentReference, Encounter, and other types.
        body = response.body
        if body.nil? || !body.is_a?(Hash) || body['entry'].blank?
          user_uuid = @user.user_account_uuid
          Rails.logger.debug { "UHD: Missing or invalid response for AVS metadata request for user #{user_uuid}." }
          return [[], []]
        end
        entries = extract_all_entries(body)
        grouped = entries.group_by { |entry| entry['resourceType'] }
        doc_ref_entries = grouped['DocumentReference'] || []
        encounter_entries = grouped['Encounter'] || []
        if doc_ref_entries.empty? || encounter_entries.empty?
          user_uuid = @user.user_account_uuid
          to_log = "DocumentReference entries: #{doc_ref_entries.size}, Encounter entries: #{encounter_entries.size}"
          Rails.logger.debug { "UHD: Missing data in AVS metadata response for user #{user_uuid}. #{to_log}" }
          return [[], []]
        end
        [doc_ref_entries, encounter_entries]
      end
    end

    # Retrieves the After Visit Summary for the given appointment ID from unified health data sources
    #
    # @param appt_id [String] The ID of the appointment to retrieve the summary for
    # NOTE: This is not the ID used by the VAOS service, but from the appointment object's `identifier` field:
    # `"identifier": [{"system": "urn:va.gov:masv2:cerner:appointment", "value": "Appointment/1234567"}]`
    #
    # @param include_binary [Boolean] Whether to include binary data in the response
    #
    # @return [Array<UnifiedHealthData::AfterVisitSummary>] Array of AVS objects
    # Because an appointment can have multiple documents associated with it
    # (e.g., AVS, discharge instructions, etc.), we return an array here
    def get_appt_avs(appt_id:, include_binary: false)
      validate_icn!
      with_monitoring do
        response = uhd_client.get_avs(patient_id: @user.icn, appt_id:)
        body = response.body
        summaries = body['entry'].select { |record| record['resource']['resourceType'] == 'DocumentReference' }
        parsed_avs_meta = summaries.map do |summary|
          clinical_notes_adapter.parse_avs_with_metadata(summary, appt_id, include_binary)
        end
        log_loinc_code_distribution(parsed_avs_meta, 'AVS')
        parsed_avs_meta.compact
      end
    end

    def get_avs_binary_data(doc_id:, appt_id:)
      validate_icn!
      with_monitoring do
        response = uhd_client.get_avs(patient_id: @user.icn, appt_id:)
        body = response.body
        summary = body['entry'].find do |record|
          record['resource']['resourceType'] == 'DocumentReference' && record['resource']['id'] == doc_id
        end
        clinical_notes_adapter.parse_avs_binary(summary)
      end
    end

    # Initiates CCD generation and returns the job status response.
    # The frontend will poll separately via get_ccd_status with the returned jobId.
    #
    # @return [UnifiedHealthData::Ccd] Parsed initiation response with job metadata
    def initiate_ccd
      validate_icn!
      with_monitoring do
        start_date = default_start_date
        end_date = default_end_date

        response = uhd_client.generate_ccd(patient_id: @user.icn, start_date:, end_date:)
        ccd = ccd_adapter.parse(response.body)
        ccd.http_status = response.status
        ccd
      end
    end

    # Retrieves status of CCD generation
    # @param job_id [String] The CCD job ID
    # @return [UnifiedHealthData::Ccd] CCD with status of task when processing (202) or of each format (200)
    def get_ccd_status(job_id:)
      with_monitoring do
        response = uhd_client.get_ccd(job_id:)
        ccd = ccd_adapter.parse(response.body)
        ccd.http_status = response.status
        ccd
      end
    end

    # Retrieves presigned url of the specified CCD format
    # @param job_id [String] The CCD job ID
    # @param format [String] The desired format: 'xml', 'pdf', or 'html'
    # @return [String, nil] The presigned URL for the specified format, or nil if not found
    def get_ccd_url(job_id:, format: 'xml')
      with_monitoring do
        response = uhd_client.get_ccd(job_id:)
        body = response.body
        ccd_adapter.parse_url(body, format:)
      end
    end

    # Retrieves a list of available CCD jobs for a user.
    # Each Task entry in the Bundle represents a CCD generation job with artifact metadata.
    #
    # @return [Array<UnifiedHealthData::Ccd>] Array of parsed CCD job objects, or empty array if no tasks found
    def get_ccd_jobs
      validate_icn!
      with_monitoring do
        response = uhd_client.get_ccd_jobs_by_user(patient_id: @user.icn)
        body = response.body

        ccd_adapter.parse_tasks(body)
      end
    end

    private

    # Extracts all resource hashes from a FHIR Bundle's entry array.
    def extract_all_entries(bundle)
      return [] unless bundle.is_a?(Hash)

      inner = bundle['resource'] || bundle
      entries = inner['entry']
      return [] unless entries.is_a?(Array)

      entries.filter_map { |entry| entry['resource'] }
    end

    # Extracts and removes warning metadata injected by the client's OperationOutcome detection.
    # Returns an empty array if no warnings are present.
    def extract_warnings(body)
      return [] unless body.is_a?(Hash)

      body.delete('_warnings') || []
    end

    def fetch_combined_records(body)
      return [] if body.nil?

      vista_records = (body.dig(SourceConstants::VISTA, 'entry') || []).map do |r|
        r.merge('source' => SourceConstants::VISTA)
      end
      oracle_health_records = (body.dig(SourceConstants::ORACLE_HEALTH, 'entry') || []).map do |r|
        r.merge('source' => SourceConstants::ORACLE_HEALTH)
      end
      vista_records + oracle_health_records
    end

    def build_refill_request_body(orders)
      {
        patientId: @user.icn,
        orders: orders.map do |order|
          {
            orderId: order[:id].to_s,
            stationNumber: order[:stationNumber].to_s
          }
        end
      }
    end

    def build_error_response(orders)
      {
        success: [],
        failed: orders.map do |order|
          { id: order[:id], error: 'Service unavailable', station_number: order[:stationNumber] }
        end
      }
    end

    def normalize_orders(orders)
      return [] if orders.blank?

      orders.map do |order|
        next order unless order.respond_to?(:with_indifferent_access)

        order.with_indifferent_access
      end
    end

    def parse_refill_response(response)
      body = response.body
      refill_items = body.is_a?(Array) ? body : []
      successes = extract_successful_refills(refill_items)
      failures = extract_failed_refills(refill_items)

      {
        success: successes || [],
        failed: failures || []
      }
    end

    def validate_refill_response_count(normalized_orders, result)
      orders_sent = normalized_orders.size
      orders_received = result[:success].size + result[:failed].size

      return if orders_sent == orders_received

      error_message = "Refill response count mismatch: sent #{orders_sent} orders, " \
                      "received #{orders_received} responses"
      Rails.logger.error(error_message)
      raise Common::Exceptions::PrescriptionRefillResponseMismatch.new(orders_sent, orders_received)
    end

    def extract_successful_refills(refill_items)
      successful_refills = refill_items.select { |item| item['success'] == true }
      successful_refills.map do |refill|
        order = refill['order'] || refill
        {
          id: order['orderId'],
          status: refill['message'] || 'submitted',
          station_number: order['stationNumber']
        }
      end
    end

    def extract_failed_refills(refill_items)
      failed_refills = refill_items.select { |item| item['success'] == false }
      failed_refills.map do |failure|
        order = failure['order'] || failure
        {
          id: order['orderId'],
          error: failure['message'] || 'Unable to process refill',
          station_number: order['stationNumber']
        }
      end
    end

    def remap_vista_identifier(records)
      records[SourceConstants::VISTA]['entry']&.each do |allergy|
        vista_identifier = allergy['resource']['identifier']&.find do |id|
          id['system'].starts_with?('https://va.gov/systems/')
        end
        next unless vista_identifier && vista_identifier['value']

        allergy['resource']['id'] = vista_identifier['value']
      end
    end

    def log_care_summaries_metrics(doc_ref_records, parsed_notes, start_date, end_date)
      clinical_notes_logging_enabled? && log_notes_response_count(doc_ref_records.size, parsed_notes.size)
      clinical_notes_logging_enabled? && log_notes_index_metrics(parsed_notes, start_date, end_date)

      doc_ref_tally = doc_ref_records.tally { |r| r['source'] }
      returned_tally = parsed_notes.tally(&:source)
      source_breakdown = {
        vista_doc_refs: doc_ref_tally[SourceConstants::VISTA] || 0,
        oh_doc_refs: doc_ref_tally[SourceConstants::ORACLE_HEALTH] || 0,
        vista_returned: returned_tally[SourceConstants::VISTA] || 0,
        oh_returned: returned_tally[SourceConstants::ORACLE_HEALTH] || 0
      }
      warn_high_filter_rate(doc_ref_records.size, parsed_notes.size, source_breakdown:)
    end

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

    def remap_vista_uid(records)
      records[SourceConstants::VISTA]['entry']&.each do |note|
        vista_uid_identifier = note['resource']['identifier']&.find { |id| id['system'] == 'vista-uid' }
        next unless vista_uid_identifier && vista_uid_identifier['value']

        new_id_array = vista_uid_identifier['value'].split(':')
        note['resource']['id'] = new_id_array[-3..].join('-')
      end
    end

    def parse_notes(records)
      return [] if records.blank?

      parsed = records.map { |record| parse_single_note(record) }
      parsed.compact
    end

    def parse_single_note(record)
      return nil if record.blank?

      clinical_notes_adapter.parse(record)
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

      doc_ref = extract_document_reference(body)
      return nil unless doc_ref

      record = { 'resource' => doc_ref }
      record['source'] = source
      parse_single_note(record)
    end

    # SCDF always returns Bundles from Oracle Health
    def extract_bundle(body, resource_type)
      return nil unless body.is_a?(Hash)

      entries = body['entry']
      return nil unless entries.is_a?(Array)

      resource_entry = entries.find do |entry|
        entry.dig('resource', 'resourceType') == resource_type
      end
      resource_entry&.dig('resource')
    end

    # Extracts the DocumentReference resource from a FHIR Bundle response.
    def extract_document_reference(body)
      extract_bundle(body, 'DocumentReference')
    end

    def uhd_client
      @uhd_client ||= UnifiedHealthData::Client.new
    end

    def validate_icn!
      raise Common::Exceptions::ParameterMissing, 'ICN' if @user&.icn.blank?
    end

    def allergy_adapter
      @allergy_adapter ||= UnifiedHealthData::Adapters::AllergyAdapter.new(user: @user)
    end

    def lab_or_test_adapter
      @lab_or_test_adapter ||= UnifiedHealthData::Adapters::LabOrTestAdapter.new(mr_log:)
    end

    def ccd_adapter
      @ccd_adapter ||= UnifiedHealthData::Adapters::CcdAdapter.new
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

    def default_start_date
      '1900-01-01'
    end

    def default_end_date
      Time.zone.today.to_s
    end

    def validate_date_param(date_string, param_name)
      Date.parse(date_string)
    rescue ArgumentError, TypeError
      raise ArgumentError, "Invalid #{param_name}: '#{date_string}'. Expected format: YYYY-MM-DD"
    end

    def normalize_date_range(start_date, end_date)
      start_date = nil if start_date.blank?
      end_date = nil if end_date.blank?
      validate_date_param(start_date, 'start_date') if start_date
      validate_date_param(end_date, 'end_date') if end_date
      [start_date || default_start_date, end_date || default_end_date]
    end
  end # rubocop:enable Metrics/ClassLength
end
