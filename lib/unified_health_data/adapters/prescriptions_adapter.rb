# frozen_string_literal: true

require_relative 'vista_prescription_adapter'
require_relative 'oracle_health_prescription_adapter'
require_relative 'v2_status_mapping'
require_relative '../constants'
require_relative '../operation_outcome_detector'

module UnifiedHealthData
  module Adapters
    class PrescriptionsAdapter
      include V2StatusMapping
      # Prescription status constants (STATUS_* / DISP_*) live in Constants::PrescriptionStatuses.
      include UnifiedHealthData::Constants::PrescriptionStatuses

      # Number of days after the most recent shipped date during which a prescription remains trackable.
      SHIPPED_TRACKING_WINDOW_DAYS = 15

      def initialize(current_user = nil)
        @current_user = current_user
        @vista_adapter = VistaPrescriptionAdapter.new
        @oracle_adapter = OracleHealthPrescriptionAdapter.new(current_user)
      end

      # @param body [Hash] The raw UHD response body
      # @param current_only [Boolean] When true, excludes discontinued/expired meds older than 180 days
      # @return [Hash] Hash with :prescriptions (Array) and :metadata (Hash) keys
      def parse(body, current_only: false)
        raise ArgumentError, 'UHD returned an empty response body' if body.nil?

        prescriptions = []

        # Parse VistA medications
        vista_medications = parse_vista_medications(body)
        prescriptions.concat(vista_medications) if vista_medications.present?

        # Parse Oracle Health medications
        oracle_medications = parse_oracle_medications(body)
        prescriptions.concat(oracle_medications) if oracle_medications.present?

        log_upstream_parse_counts(
          vista_count: vista_medications.size,
          oracle_count: oracle_medications.size,
          body:
        )

        # Exclude certain prescriptions based on business rules
        prescriptions.reject! { |prescription| should_exclude_prescription?(prescription) }

        # Apply current filtering if requested
        prescriptions = apply_current_filtering(prescriptions) if current_only

        # Apply shipped tracking logic (sets is_trackable to false if shipped beyond 15-day window)
        if Flipper.enabled?(:mhv_medications_management_improvements, @current_user)
          apply_shipped_tracking_logic(prescriptions)
          apply_awaiting_tracking_logic(prescriptions)
        end

        # Apply V2 status mapping to all prescriptions when Cerner pilot flag is enabled
        # This is the single point where V2 status mapping is applied for both VistA and Oracle Health
        prescriptions = apply_v2_status_mapping_if_enabled(prescriptions)

        { prescriptions:, metadata: { has_failed_stations: any_source_failed?(body) } }
      end

      private

      def apply_current_filtering(prescriptions)
        filtered = prescriptions.reject { |prescription| prescription_not_current?(prescription) }

        Rails.logger.info(
          message: 'Applied current filtering to prescriptions',
          original_count: prescriptions.size,
          filtered_count: filtered.size,
          excluded_count: prescriptions.size - filtered.size
        )

        filtered
      end

      def prescription_not_current?(prescription)
        # Exclude discontinued/expired medications that are older than 180 days
        if %w[discontinued expired].include?(prescription.refill_status) &&
           prescription.expiration_date.present?
          begin
            expiration_date = Date.parse(prescription.expiration_date)
            return true if expiration_date < 180.days.ago
          rescue Date::Error, TypeError
            # If date parsing fails, don't exclude based on date
            # Only log last 4 digits of prescription ID for privacy
            rx_suffix = prescription.id.to_s.last(4)
            Rails.logger.warn("Invalid expiration date for rx ending in #{rx_suffix}: #{prescription.expiration_date}")
          end
        end

        false
      end

      def should_exclude_prescription?(prescription)
        # Mirror logic from Mobile::V0::PrescriptionsController#resource_data_modifications

        # Exclude Partial Fill (PF) and Pending Prescriptions (PD)
        display_pending_meds = Flipper.enabled?(:mhv_medications_display_pending_meds, @current_user)
        if display_pending_meds
          return true if prescription.prescription_source == 'PF'
        elsif %w[PF PD].include?(prescription.prescription_source)
          # TODO: remove this line when PF and PD are allowed on the app
          return true
        end

        # Exclude inpatient prescriptions
        # See https://build.fhir.org/valueset-medicationrequest-admin-location.html
        return true if prescription.category&.include?('inpatient')

        false
      end

      def parse_vista_medications(body)
        vista_data = body[SourceConstants::VISTA]
        return [] unless vista_data && vista_data['medicationList']

        medications = vista_data.dig('medicationList', 'medication')
        return [] unless medications.is_a?(Array)

        medications.map { |med| @vista_adapter.parse(med) }.compact
      end

      def parse_oracle_medications(body)
        oracle_data = body[SourceConstants::ORACLE_HEALTH]
        return [] unless oracle_data && oracle_data['entry']

        entries = oracle_data['entry']
        return [] unless entries.is_a?(Array)

        # Filter for MedicationRequest resources
        medication_requests = entries.select do |entry|
          entry.dig('resource', 'resourceType') == 'MedicationRequest'
        end

        medication_requests.map { |entry| @oracle_adapter.parse(entry['resource']) }.compact
      end

      # For prescriptions with disp_status 'Active: Shipped', checks the tracking shipped date
      # against a 15-day window. If shipped beyond 15 days, sets is_trackable to false.
      def apply_shipped_tracking_logic(prescriptions)
        prescriptions.each do |rx|
          next unless rx.disp_status == DISP_ACTIVE_SHIPPED

          most_recent_date = most_recent_shipped_date(rx)
          next unless most_recent_date

          rx.is_trackable = false unless most_recent_date >= SHIPPED_TRACKING_WINDOW_DAYS.days.ago
        end
      end

      def most_recent_shipped_date(rx)
        dates = rx.tracking.filter_map do |t|
          Time.zone.parse(t[:complete_date_time])
        rescue ArgumentError, TypeError
          nil
        end
        dates.max
      end

      # Applies V2 status mapping to all prescriptions when V2 status mapping flag is enabled
      # This is the single consolidation point for V2 status mapping for both VistA and Oracle Health
      # @param prescriptions [Array] Array of prescription objects
      # @return [Array] The same array with prescription statuses mapped (if flag enabled)
      def apply_v2_status_mapping_if_enabled(prescriptions)
        return prescriptions unless Flipper.enabled?(:mhv_medications_v2_status_mapping, @current_user)

        apply_v2_status_mapping_to_all(prescriptions)
      end

      # For prescriptions that have been recently dispensed (filled) but do not yet have
      # shipping/tracking information, reclassifies them as an in-progress refill. This covers
      # the gap between "Refill in progress" and "Refill shipped": once a fill completes the
      # prescription returns to an 'Active' disp_status with a dispensed date set, but no
      # tracking entry exists until the pharmacy ships it. Rather than surfacing a distinct
      # state, we treat the fill as "Refill in Process" so every surface renders the existing
      # in-progress treatment. The same 15-day window used for shipped tracking bounds how long
      # we keep a fill in this state. is_awaiting_tracking is retained as the detection signal.
      #
      # @param prescriptions [Array<UnifiedHealthData::Prescription>] parsed prescriptions, mutated in place
      # @return [void]
      def apply_awaiting_tracking_logic(prescriptions)
        prescriptions.each do |rx|
          awaiting = awaiting_tracking?(rx)
          rx.is_awaiting_tracking = awaiting
          next unless awaiting

          rx.disp_status = DISP_ACTIVE_REFILL_IN_PROCESS
          rx.refill_status = STATUS_REFILL_IN_PROCESS
          # There is no shipment yet, so there is nothing to track. Clear is_trackable so a
          # tracking affordance is not offered against an empty/incomplete tracking list.
          rx.is_trackable = false
        end
      end

      # Determines whether a prescription is a recently dispensed fill that is still
      # awaiting shipping/tracking information. Qualifies only when the prescription is
      # 'Active', has no tracking entry yet, and its most recent dispensed date falls
      # within the shipped-tracking window.
      #
      # @param rx [UnifiedHealthData::Prescription] the prescription to evaluate
      # @return [Boolean] true when the fill is awaiting tracking, false otherwise
      def awaiting_tracking?(rx)
        return false unless rx.disp_status == DISP_ACTIVE
        return false if recent_tracking?(rx)

        dispensed_date = most_recent_dispensed_date(rx)
        return false unless dispensed_date

        # sorted_dispensed_date is date-only, so compare at date granularity to keep
        # the 15-day boundary inclusive regardless of the current time of day.
        dispensed_date.to_date >= SHIPPED_TRACKING_WINDOW_DAYS.days.ago.to_date
      end

      # If any tracking entry has a completion date, the fill has shipped and is
      # therefore not awaiting tracking. Checks every entry (not just the first)
      # because tracking can contain multiple entries and any of them may carry the
      # completion date, while others can have a blank complete_date_time.
      #
      # @param rx [UnifiedHealthData::Prescription] the prescription to evaluate
      # @return [Boolean] true when a tracking entry with a completion date exists
      def recent_tracking?(rx)
        return false if rx.tracking.blank?

        rx.tracking.any? do |t|
          t.is_a?(Hash) && t[:complete_date_time].present?
        end
      end

      def most_recent_dispensed_date(rx)
        raw = rx.sorted_dispensed_date.presence || rx.dispensed_date.presence
        return nil if raw.blank?

        Time.zone.parse(raw.to_s)
      rescue ArgumentError, TypeError
        nil
      end

      # Checks whether either data source reported a failure in the UHD response.
      # VistA: failedStationList is a non-empty string (comma-separated station numbers).
      # Oracle Health: entry array contains an OperationOutcome resource with error-severity issues.
      def any_source_failed?(body)
        vista_failed?(body) || oracle_health_failed?(body)
      end

      def vista_failed?(body)
        body.dig(SourceConstants::VISTA, 'failedStationList').present?
      end

      # Defense-in-depth: today the Client raises UpstreamPartialFailure for
      # error/fatal OperationOutcomes before the adapter runs, so this branch
      # is not reachable. We keep it aligned with OperationOutcomeDetector's
      # ERROR_SEVERITIES so the flag stays correct if that upstream flow changes.
      def oracle_health_failed?(body)
        oracle_data = body[SourceConstants::ORACLE_HEALTH]
        return false if oracle_data.blank?

        entries = oracle_data['entry']
        return false unless entries.is_a?(Array) && entries.present?

        entries.any? do |e|
          next false unless e.dig('resource', 'resourceType') == 'OperationOutcome'

          issues = e.dig('resource', 'issue')
          issues.is_a?(Array) && issues.any? do |i|
            OperationOutcomeDetector::ERROR_SEVERITIES.include?(i['severity'])
          end
        end
      end

      # Logs the raw counts from each data source after initial parsing.
      # This is the earliest point where we know what the upstream returned
      def log_upstream_parse_counts(vista_count:, oracle_count:, body:)
        vista_data = body[SourceConstants::VISTA]
        oracle_data = body[SourceConstants::ORACLE_HEALTH]

        Rails.logger.info(
          message: 'UHD prescriptions upstream parse counts',
          vista_raw_medications_parsed: vista_count,
          oracle_raw_medications_parsed: oracle_count,
          vista_medication_list_is_array: vista_data&.dig('medicationList', 'medication').is_a?(Array),
          oracle_entry_is_array: oracle_data&.dig('entry').is_a?(Array),
          vista_failed_station_list: vista_data&.dig('failedStationList').presence,
          service: 'unified_health_data'
        )
      end
    end
  end
end
