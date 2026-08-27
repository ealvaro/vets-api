# frozen_string_literal: true

module UnifiedHealthData
  module Adapters
    # Determines refillability for Oracle Health FHIR MedicationRequest resources
    # Implements gate-check logic for VA prescription refill eligibility
    #
    # This module is designed to be included in OracleHealthPrescriptionAdapter
    # and has dependencies on methods from the including class and other mixed-in modules:
    #
    # Required methods from other modules (via include):
    # - categorize_medication(resource) - From OracleHealthCategorizer
    # - non_va_med?(resource) - From OracleHealthCategorizer
    # - medication_dispenses(resource) - From FhirHelpers
    # - completed_dispense_exists?(resource) - From FhirHelpers
    # - find_most_recent_medication_dispense(medication_request) - From FhirHelpers
    # - parse_expiration_date_utc(resource) - From FhirHelpers
    # - prescription_expired?(resource) - From FhirHelpers
    module OracleHealthRefillHelper
      # Determines if a medication is refillable based on gate checks
      # A medication is refillable only if ALL gate conditions pass
      #
      # Gate 1: Not a non-VA medication
      # Gate 2: MedicationRequest.status == 'active'
      # Gate 3: Prescription not expired
      # Gate 4: Refills remaining > 0
      # Gate 5: At least one completed dispense exists
      # Gate 6: Most recent dispense is not in-progress
      # Gate 7: No pending refill request (refill_status not 'submitted', and not 'refillinprocess'
      #         when the interim refill-status bridging flag is enabled)
      #
      # @param resource [Hash] FHIR MedicationRequest resource
      # @param refill_status [String] Current refill status
      # @return [Boolean] true if refillable
      def refillable?(resource, refill_status)
        return false if non_va_med?(resource)
        return false unless resource['status'] == 'active'
        return false unless prescription_not_expired?(resource)
        return false unless extract_refill_remaining(resource).positive?
        return false unless completed_dispense_exists?(resource)
        return false if most_recent_dispense_in_progress?(resource)
        return false if pending_refill_status?(refill_status)

        true
      end

      # Whether the Medications Management Improvements (MMI) rollout gate is on for the user.
      # Shared by the refill-status flag checks so each new flag ships only to the MMI cohort.
      def mmi_enabled?
        Flipper.enabled?(:mhv_medications_management_improvements, @current_user)
      end

      # Whether the OH in-progress refill-status card is enabled (flag + MMI).
      def in_progress_refill_status_enabled?
        Flipper.enabled?(:mhv_medications_oh_in_progress_refill_status, @current_user) && mmi_enabled?
      end

      # Whether the OH in-flight refill-status overlay is enabled (flag + MMI).
      def in_flight_refill_status_enabled?
        Flipper.enabled?(:mhv_medications_oh_refill_in_flight_status, @current_user) && mmi_enabled?
      end

      # Refill statuses that indicate an in-flight request and therefore block refillability.
      # 'refillinprocess' is only treated as pending while the in-process refill-block flag (+ MMI)
      # is enabled; otherwise only 'submitted' blocks refillability.
      #
      # @param refill_status [String] Current refill status
      # @return [Boolean] true if the status represents a pending refill request
      def pending_refill_status?(refill_status)
        pending_statuses = %w[submitted]
        if Flipper.enabled?(:mhv_medications_oh_refill_in_process_block, @current_user) && mmi_enabled?
          pending_statuses << 'refillinprocess'
        end
        pending_statuses.include?(refill_status)
      end

      # Checks if prescription expiration date is in the future
      # Returns false if expiration date is missing (not refillable for safety)
      #
      # @param resource [Hash] FHIR MedicationRequest resource
      # @return [Boolean] true if not expired, false if expired or missing expiration date
      def prescription_not_expired?(resource)
        expiration_date = parse_expiration_date_utc(resource)
        return false if expiration_date.nil? # No expiration date = not refillable for safety

        !prescription_expired?(resource)
      end

      # Calculates refills remaining for the medication
      # Non-VA medications always return 0 refills
      #
      # @param resource [Hash] FHIR MedicationRequest resource
      # @return [Integer] Number of refills remaining
      def extract_refill_remaining(resource)
        return 0 if non_va_med?(resource)

        repeats_allowed = resource.dig('dispenseRequest', 'numberOfRepeatsAllowed') || 0
        dispenses_completed = medication_dispenses(resource).count { |d| d['status'] == 'completed' }

        remaining = repeats_allowed - [dispenses_completed - 1, 0].max
        remaining.positive? ? remaining : 0
      end

      # Dispense statuses that mean a fill is somewhere between requested and handed
      # over. Per the refillability spec (Gate 7) and the content document, all three
      # map to the "Active: Refill in Process" family ("also known as Active: Suspended").
      IN_PROGRESS_DISPENSE_STATUSES = %w[preparation in-progress on-hold].freeze

      # Checks if a fill is currently in progress for the medication.
      #
      # @param resource [Hash] FHIR MedicationRequest resource
      # @return [Boolean] true if a fill is in progress
      def most_recent_dispense_in_progress?(resource)
        most_recent = find_most_recent_medication_dispense(resource)
        return true if most_recent && IN_PROGRESS_DISPENSE_STATUSES.include?(most_recent['status'])

        # A fill that has begun but not yet been handed over carries no whenHandedOver/
        # whenPrepared date, so find_most_recent_medication_dispense sinks it to epoch and
        # an older completed fill wins the date ranking -- masking the active fill. Detect
        # such a not-yet-handed-over in-progress dispense directly so the card reflects
        # "Refill in Process" instead of falling back to the requested-Task "Submitted".
        # Gated together with MMI so the improved in-progress detection ships only to the
        # MMI rollout cohort.
        return false unless Flipper.enabled?(:mhv_medications_oh_in_progress_refill_status, @current_user) &&
                            Flipper.enabled?(:mhv_medications_management_improvements, @current_user)

        medication_dispenses(resource).any? do |dispense|
          IN_PROGRESS_DISPENSE_STATUSES.include?(dispense['status']) && dispense['whenHandedOver'].blank?
        end
      end
    end
  end
end
