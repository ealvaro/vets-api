# frozen_string_literal: true

require_relative '../facility_service'
require_relative 'facility_name_resolver'
require_relative 'date_time_helpers'
require_relative 'medication_dispense_helpers'
require_relative 'oracle_health_categorizer'
require_relative 'oracle_health_expiration_helper'
require_relative 'oracle_health_refill_helper'
require_relative 'oracle_health_renewal_flow_helper'
require_relative 'oracle_health_renewability_helper'
require_relative 'oracle_health_task_helper'
require_relative 'oracle_health_tracking_helper'

module UnifiedHealthData
  module Adapters
    class OracleHealthPrescriptionAdapter
      include DateTimeHelpers
      include MedicationDispenseHelpers
      include OracleHealthCategorizer
      include OracleHealthExpirationHelper
      include OracleHealthRefillHelper
      include OracleHealthRenewalFlowHelper
      include OracleHealthRenewabilityHelper
      include OracleHealthTaskHelper
      include OracleHealthTrackingHelper

      DEFAULT_FILTERED_STATUSES = %w[cancelled entered-in-error].freeze

      # Internal refill status values
      STATUS_ACTIVE = 'active'
      STATUS_SUBMITTED = 'submitted'
      STATUS_REFILL_IN_PROCESS = 'refillinprocess'
      STATUS_PROVIDER_HOLD = 'providerHold'
      STATUS_DISCONTINUED = 'discontinued'
      STATUS_EXPIRED = 'expired'
      STATUS_PENDING = 'pending'
      STATUS_UNKNOWN = 'unknown'

      # Display status values (user-facing)
      DISP_ACTIVE = 'Active'
      DISP_ACTIVE_NON_VA = 'Active: Non-VA'
      DISP_ACTIVE_SUBMITTED = 'Active: Submitted'
      DISP_ACTIVE_REFILL_IN_PROCESS = 'Active: Refill in Process'
      DISP_ACTIVE_ON_HOLD = 'Active: On hold'
      DISP_DISCONTINUED = 'Discontinued'
      DISP_EXPIRED = 'Expired'
      DISP_UNKNOWN = 'Unknown'

      def initialize(current_user = nil)
        @current_user = current_user
      end

      # Parses an Oracle Health FHIR MedicationRequest into a UnifiedHealthData::Prescription
      #
      # @param resource [Hash] FHIR MedicationRequest resource from Oracle Health
      # @return [UnifiedHealthData::Prescription, nil] Parsed prescription or nil if invalid/filtered
      def parse(resource)
        return nil if resource.nil? || resource['id'].nil?
        return nil if filtered_status?(resource['status'])

        category = categorize_medication(resource)

        # Filter out medications that should not be visible to Veterans
        return nil if %i[pharmacy_charges inpatient clinic_administered].include?(category)

        log_uncategorized_medication(resource) if category == :uncategorized

        UnifiedHealthData::Prescription.new(build_prescription_attributes(resource))
      rescue => e
        Rails.logger.error("Error parsing Oracle Health prescription: #{e.message}")
        nil
      end

      private

      def filtered_status?(status)
        filtered_statuses.include?(status)
      end

      # Returns the list of FHIR MedicationRequest statuses to filter out.
      # Configurable via Settings.mhv.uhd.medication_filtered_statuses (comma-separated).
      # Defaults to cancelled and entered-in-error. Set to "none" to disable filtering.
      def filtered_statuses
        @filtered_statuses ||= begin
          configured = Settings.mhv.uhd.medication_filtered_statuses
          if configured.present?
            values = configured.to_s.split(',').map(&:strip)
            values == ['none'] ? [] : values
          else
            DEFAULT_FILTERED_STATUSES
          end
        end
      end

      def build_prescription_attributes(resource)
        tracking_data = build_tracking_information(resource)
        dispenses_data = build_dispenses_information(resource)
        refill_metadata = extract_refill_submission_metadata_from_tasks(resource, dispenses_data)
        renewal_metadata = extract_renewal_submission_metadata_from_tasks(resource)

        # monitoring for dispenses without tracking data, which may indicate CMOP issues
        log_completed_dispense_without_tracking(resource, tracking_data, dispenses_data)

        build_core_attributes(resource, dispenses_data)
          .merge(build_tracking_attributes(tracking_data))
          .merge(build_contact_and_source_attributes(resource, dispenses_data))
          .merge(dispenses: dispenses_data)
          .merge(refill_metadata)
          .merge(renewal_metadata)
          .merge(sorted_dispensed_date: extract_sorted_dispensed_date(dispenses_data))
          .merge(source_ehr: UnifiedHealthData::Prescription::SOURCE_EHR_ORACLE_HEALTH)
      end

      # Builds core prescription attributes from the FHIR MedicationRequest resource.
      # Note: refill_submit_date is set to nil here and later overridden by
      # extract_refill_submission_metadata_from_tasks in build_prescription_attributes.
      # This allows refill_metadata to be computed after dispenses_data is available
      # (needed to determine if a subsequent dispense exists for the refill).
      def build_core_attributes(resource, dispenses_data = [])
        refill_status = extract_refill_status(resource, dispenses_data)
        facility_name = extract_facility_name(resource)
        {
          id: resource['id'],
          type: 'Prescription',
          refill_status:,
          refill_submit_date: nil,
          refill_date: extract_refill_date(resource),
          refill_remaining: extract_refill_remaining(resource),
          facility_name:,
          ordered_date: resource['authoredOn'],
          quantity: extract_quantity(resource),
          expiration_date: extract_expiration_date(resource),
          prescription_number: extract_prescription_number(resource),
          prescription_name: extract_prescription_name(resource),
          station_number: extract_station_number(resource),
          cmop_ndc_number: nil # Not available in Oracle Health yet, will get this when we get CMOP data
        }.merge(build_availability_flags(resource, facility_name, refill_status))
      end

      # Builds boolean availability flags for a prescription.
      #
      # @param resource [Hash] FHIR MedicationRequest resource
      # @param facility_name [String, nil] Resolved facility name (must be present for refillable/renewable)
      # @param refill_status [String] Current refill status
      # @return [Hash] Hash with :is_refillable, :is_renewable, :is_renewal_flow_enabled
      def build_availability_flags(resource, facility_name, refill_status)
        is_renewable = extract_is_renewable(resource)
        station = extract_station_number(resource)
        {
          is_refillable: facility_name.present? && extract_is_refillable(resource, refill_status),
          is_renewable:,
          is_renewal_flow_enabled: facility_name.present? &&
            compute_renewal_flow_enabled(is_renewable, station, @current_user)
        }
      end

      def build_tracking_attributes(tracking_data)
        {
          is_trackable: tracking_data.any?,
          tracking: tracking_data
        }
      end

      def build_contact_and_source_attributes(resource, dispenses_data = [])
        refill_status = extract_refill_status(resource, dispenses_data)
        prescription_source = extract_prescription_source(resource)
        facility_phone = extract_facility_phone_from_extensions(resource)
        {
          instructions: extract_instructions(resource),
          facility_phone_number: facility_phone,
          cmop_division_phone: facility_phone,
          dial_cmop_division_phone: strip_phone_to_digits(facility_phone),
          prescription_source:,
          category: extract_category(resource),
          disclaimer: nil,
          provider_name: extract_provider_name(resource),
          indication_for_use: extract_indication_for_use(resource),
          remarks: extract_remarks(resource),
          disp_status: map_refill_status_to_disp_status(refill_status, prescription_source)
        }
      end

      def build_dispenses_information(resource)
        contained_resources = resource['contained'] || []
        dispenses = contained_resources.select { |c| c.is_a?(Hash) && c['resourceType'] == 'MedicationDispense' }

        dispenses.map do |dispense|
          {
            status: dispense['status'],
            refill_date: dispense['whenHandedOver'],
            when_prepared: dispense['whenPrepared'],
            when_handed_over: dispense['whenHandedOver'],
            facility_name: facility_resolver.resolve_facility_name(dispense),
            instructions: extract_sig_from_dispense(dispense),
            quantity: format_quantity(dispense.dig('quantity', 'value')),
            prescription_name: dispense.dig('medicationCodeableConcept', 'text'),
            id: dispense['id'],
            refill_submit_date: nil,
            prescription_number: nil,
            remarks: nil,
            disclaimer: nil
          }.merge(cmop_dispense_fields)
        end
      end

      # CMOP-related fields not available in Oracle Health yet
      # Extracted to separate method to keep build_dispenses_information under line limit
      #
      # @return [Hash] Hash of CMOP-related nil fields
      def cmop_dispense_fields
        {
          cmop_division_phone: nil,
          cmop_ndc_number: nil,
          dial_cmop_division_phone: nil
        }
      end

      def extract_refill_date(resource)
        dispense = find_most_recent_medication_dispense(resource)
        return dispense['whenHandedOver'] if dispense&.dig('whenHandedOver')

        nil
      end

      # Returns the most recent fill date from OH dispenses.
      # Prefers when_handed_over, falls back to when_prepared.
      # Uses safe date coercion so one bad date string doesn't drop the entire prescription.
      def extract_sorted_dispensed_date(dispenses_data)
        dates = dispenses_data.filter_map do |d|
          raw = d[:when_handed_over] || d[:when_prepared]
          raw&.to_date
        rescue ArgumentError, TypeError
          nil
        end
        max_date = dates.max
        max_date&.to_s
      end

      # Extracts and normalizes MedicationRequest status to VistA-compatible values
      # Checks for successful submitted refills based on Task resources
      #
      # @param resource [Hash] FHIR MedicationRequest resource
      # @param dispenses_data [Array<Hash>] Array of dispense data for checking subsequent dispenses
      # @return [String] VistA-compatible status value
      def extract_refill_status(resource, dispenses_data = [])
        # Check if there's a successful submitted refill (no subsequent dispense)
        contained_resources = resource['contained'] || []
        medication_request_id = resource['id']

        # Find successful refill tasks: intent='order', status='requested', matching focus reference
        successful_refill_tasks = contained_resources.select do |c|
          c.is_a?(Hash) &&
            c['resourceType'] == 'Task' &&
            c['intent'] == 'order' &&
            c['status'] == 'requested' &&
            task_references_medication_request?(c, medication_request_id)
        end

        if successful_refill_tasks.any?
          # Get most recent task by executionPeriod.start
          most_recent_task = successful_refill_tasks.max_by do |task|
            parse_date_or_epoch(task.dig('executionPeriod', 'start'))
          end

          task_submit_date = most_recent_task.dig('executionPeriod', 'start')
          return STATUS_SUBMITTED if task_submit_date && !subsequent_dispense?(task_submit_date, dispenses_data)
        end

        normalize_to_legacy_vista_status(resource)
      end

      # Maps refill_status to user-friendly disp_status for display
      # When disp_status is nil (UHD service), derive it from refill_status
      #
      # @param refill_status [String] Internal refill status code
      # @param prescription_source [String] Source of prescription (VA, NV, etc.)
      # @return [String] User-friendly display status
      def map_refill_status_to_disp_status(refill_status, prescription_source)
        # Special case: active + Non-VA source
        return DISP_ACTIVE_NON_VA if refill_status == STATUS_ACTIVE && prescription_source == 'NV'

        # Standard mapping
        case refill_status
        when STATUS_ACTIVE
          DISP_ACTIVE
        when STATUS_SUBMITTED
          DISP_ACTIVE_SUBMITTED
        when STATUS_REFILL_IN_PROCESS
          DISP_ACTIVE_REFILL_IN_PROCESS
        when STATUS_PROVIDER_HOLD
          DISP_ACTIVE_ON_HOLD
        when STATUS_DISCONTINUED
          DISP_DISCONTINUED
        when STATUS_EXPIRED
          DISP_EXPIRED
        when STATUS_UNKNOWN, STATUS_PENDING
          DISP_UNKNOWN
        else
          # Fallback for unexpected values
          Rails.logger.warn("Unexpected refill_status for disp_status mapping: #{refill_status}")
          DISP_UNKNOWN
        end
      end

      # Maps Oracle Health FHIR MedicationRequest status to VistA-equivalent status
      # Based on legacy VistA status mapping requirements
      #
      # @param resource [Hash] FHIR MedicationRequest resource
      # @return [String] VistA-compatible status value
      def normalize_to_legacy_vista_status(resource)
        mr_status = resource['status']
        refills_remaining = extract_refill_remaining(resource)
        expiration_date = parse_expiration_date_utc(resource)
        has_in_progress_dispense = most_recent_dispense_in_progress?(resource)

        normalized_status = map_fhir_status_to_vista(
          mr_status,
          refills_remaining,
          expiration_date,
          has_in_progress_dispense,
          resource
        )

        log_status_normalization(resource, mr_status, normalized_status, refills_remaining, has_in_progress_dispense)

        normalized_status
      end

      # Maps FHIR MedicationRequest status to VistA equivalent using business rules
      #
      # @param mr_status [String] FHIR MedicationRequest.status
      # @param refills_remaining [Integer] Number of refills remaining
      # @param expiration_date [Time, nil] Parsed UTC expiration date
      # @param has_in_progress_dispense [Boolean] Whether the most recent dispense is in-progress
      # @return [String] VistA-compatible status value
      def map_fhir_status_to_vista(mr_status, refills_remaining, expiration_date, has_in_progress_dispense,
                                   resource = nil)
        case mr_status
        when 'active'
          normalize_active_status(refills_remaining, expiration_date, has_in_progress_dispense, resource)
        when 'on-hold'
          STATUS_PROVIDER_HOLD
        when 'cancelled', 'entered-in-error', 'stopped', 'completed'
          STATUS_DISCONTINUED
        when 'draft'
          STATUS_PENDING
        when 'unknown'
          STATUS_UNKNOWN
        else
          Rails.logger.warn("Unexpected MedicationRequest status: #{mr_status}")
          STATUS_UNKNOWN
        end
      end

      # Logs status normalization details for monitoring
      #
      # @param resource [Hash] FHIR MedicationRequest resource
      # @param original_status [String] Original FHIR status
      # @param normalized_status [String] Normalized VistA status
      # @param refills_remaining [Integer] Number of refills remaining
      # @param has_in_progress_dispense [Boolean] Whether the most recent dispense is in-progress
      def log_status_normalization(resource, original_status, normalized_status, refills_remaining,
                                   has_in_progress_dispense)
        prescription_id_suffix = resource['id']&.to_s&.last(3) || 'unknown'

        Rails.logger.info(
          message: 'Oracle Health status normalized',
          prescription_id_suffix:,
          original_status:,
          normalized_status:,
          refills_remaining:,
          has_in_progress_dispense:,
          service: 'unified_health_data'
        )
      end

      # Logs and tracks when we have completed dispenses but no tracking info.
      # This may indicate CMOP marked the dispense as filled but never shipped.
      # @param resource [Hash] FHIR MedicationRequest resource
      # @param tracking_data [Array] Tracking information
      # @param dispenses_data [Array<Hash>] Dispense information
      #
      def log_completed_dispense_without_tracking(resource, tracking_data, dispenses_data)
        return if tracking_data.any?

        completed_dispenses = dispenses_data.select do |d|
          d[:status] == 'completed'
        end
        return if completed_dispenses.empty?

        prescription_id_suffix = resource['id']&.to_s&.last(3) || 'unknown'
        dispense_ids = completed_dispenses.map do |d|
          d[:id]
        end.join(', ')

        Rails.logger.warn(
          message: 'Completed dispenses without tracking data',
          prescription_id_suffix:,
          dispense_ids:,
          service: 'unified_health_data'
        )

        StatsD.increment('unified_health_data.prescriptions.completed_dispense_without_tracking')
      end

      # Determines VistA status for 'active' MedicationRequest based on business rules
      #
      # @param refills_remaining [Integer] Number of refills remaining
      # @param expiration_date [Time, nil] Parsed UTC expiration date
      # @param has_in_progress_dispense [Boolean] Whether the most recent dispense is in-progress
      # @return [String] VistA status value
      def normalize_active_status(_refills_remaining, expiration_date, has_in_progress_dispense, resource = nil)
        # Rule: Most recent dispense is in-progress → refillinprocess
        # This takes priority over expired status since an active refill is being processed
        return STATUS_REFILL_IN_PROCESS if has_in_progress_dispense

        # Rule: Past expiration date → expired (UNLESS it's a Non-VA medication)
        is_non_va = resource && non_va_med?(resource)
        is_past_expiration = expiration_date && expiration_date < Time.current.utc
        return STATUS_EXPIRED if is_past_expiration && !is_non_va

        # Default: active
        STATUS_ACTIVE
      end

      def extract_facility_name(resource)
        dispense = find_most_recent_medication_dispense(resource)
        facility_resolver.resolve_facility_name(dispense)
      end

      def extract_quantity(resource)
        # Primary: dispenseRequest.quantity.value
        quantity = resource.dig('dispenseRequest', 'quantity', 'value')
        return format_quantity(quantity) if quantity

        # Fallback: check contained MedicationDispense
        dispense = find_most_recent_medication_dispense(resource)
        return format_quantity(dispense.dig('quantity', 'value')) if dispense

        nil
      end

      # Formats a quantity value by removing trailing zeros.
      # @param value [Numeric, String, nil] The quantity value to format
      # @return [String, nil] The formatted quantity string without trailing zeros, or nil if value is nil.
      #   Returns the original value as a string if BigDecimal conversion fails.
      def format_quantity(value)
        return nil if value.nil?

        # Convert to BigDecimal for precise handling, then to string without trailing zeros
        BigDecimal(value.to_s).to_s('F').sub(/\.?0+$/, '')
      rescue ArgumentError
        value.to_s
      end

      def extract_prescription_number(resource)
        identifiers = resource['identifier'] || []
        rx_number = identifiers.find { |id| id['system'] == 'http://va.gov/identifier/rx-number' }&.dig('value')
        station_prefix = identifiers.find do |id|
          id['system'] == 'http://va.gov/identifier/station-prefix'
        end&.dig('value')
        missing_station_prefix = station_prefix.blank?
        missing_rx_number = rx_number.blank?
        if missing_station_prefix || missing_rx_number
          log_missing_prescription_identifiers(resource, station_prefix, missing_station_prefix, missing_rx_number)
          return nil
        end

        "#{station_prefix}-#{rx_number}"
      end

      def log_missing_prescription_identifiers(resource, station_prefix, missing_station_prefix, missing_rx_number)
        log_payload = {
          prescription_id_suffix: resource['id']&.to_s&.last(6),
          station_prefix: station_prefix.presence,
          missing_station_prefix:,
          missing_rx_number:
        }
        if missing_station_prefix && missing_rx_number
          Rails.logger.debug('Oracle Health prescription missing both identifiers', **log_payload)
        else
          Rails.logger.warn('Oracle Health prescription missing identifier', **log_payload)
        end
      end

      def extract_prescription_name(resource)
        resource.dig('medicationCodeableConcept', 'text') ||
          resource.dig('medicationReference', 'display')
      end

      def extract_station_number(resource)
        dispense = find_most_recent_medication_dispense(resource)
        raw_station_number = dispense&.dig('location', 'display')
        return nil unless raw_station_number

        # Extract first 3 digits from format like "556-RX-MAIN-OP"
        match = raw_station_number.match(/^(\d{3})/)
        if match
          match[1]
        else
          Rails.logger.warn("Unable to extract 3-digit station number from: #{raw_station_number}")
          raw_station_number
        end
      end

      def extract_is_refillable(resource, refill_status)
        refillable?(resource, refill_status)
      end

      def extract_is_renewable(resource)
        renewable?(resource)
      end

      def extract_instructions(resource)
        dosage_instructions = resource['dosageInstruction'] || []
        return nil if dosage_instructions.empty?

        first_instruction = dosage_instructions.first

        # Use patientInstruction if available (more user-friendly)
        return first_instruction['patientInstruction'] if first_instruction['patientInstruction']

        # Otherwise use text
        return first_instruction['text'] if first_instruction['text']

        # Build from components
        build_instruction_text(first_instruction)
      end

      def extract_prescription_source(resource)
        non_va_med?(resource) ? 'NV' : 'VA'
      end

      def extract_provider_name(resource)
        resource.dig('requester', 'display')
      end

      def extract_indication_for_use(resource)
        # Extract indication from FHIR MedicationRequest.reasonCode
        reason_codes = resource['reasonCode'] || []
        return nil if reason_codes.empty?

        # reasonCode is an array of CodeableConcept objects
        # Concatenate text from all reasonCode entries
        texts = reason_codes.filter_map { |reason_code| reason_code['text'] }
        texts.join('; ') if texts.any?
      end

      def extract_remarks(resource)
        # Concatenate all MedicationRequest.note.text fields
        notes = resource['note'] || []
        return nil if notes.empty?

        note_texts = notes.filter_map { |note| note['text'].presence }
        return nil if note_texts.empty?

        note_texts.join(' ')
      end

      # Strips a phone number to digits only, truncating at extension characters.
      # Mirrors WebUtility.getPhoneNumberDialFormat() in mhv-np-rxrefill-api, which
      # truncates at extension chars (x, X, e, E, #) then strips formatting.
      # For VistA prescriptions, MHV's rxrefill API computes this server-side via
      # PrescriptionDTO.getDialCmopDivisionPhone(). For Oracle Health prescriptions
      # there is no rxrefill API in the path, so we replicate that logic here.
      #
      # @param phone [String, nil] Formatted phone number (e.g., '(800) 784-8381')
      # @return [String, nil] Digits-only string (e.g., '8007848381') or nil
      def strip_phone_to_digits(phone)
        return nil if phone.blank?

        # Truncate at extension characters (x, X, e, E, #) then strip non-digits
        phone.split(/[xXeE#]/).first&.gsub(/\D/, '').presence
      end

      def facility_resolver
        @facility_resolver ||= FacilityNameResolver.new
      end

      def facility_timezone_service
        @facility_timezone_service ||= UnifiedHealthData::FacilityService.new
      end
    end
  end
end
