# frozen_string_literal: true

require_relative 'renewal_window'

module UnifiedHealthData
  module Adapters
    # Determines Oracle Health prescription renewability using gate-check logic.
    #
    # @note Designed to be included in OracleHealthPrescriptionAdapter.
    #   Requires these methods from the including class:
    #   - extract_refill_remaining(resource) - Returns Integer of remaining refills
    #
    #   Requires these methods from other modules (via include):
    #   - categorize_medication(resource) - From OracleHealthCategorizer
    #   - non_va_med?(resource) - From OracleHealthCategorizer
    #   - medication_dispenses(resource) - From FhirHelpers
    #   - completed_dispense_exists?(resource) - From FhirHelpers
    #   - parse_expiration_date_utc(resource) - From FhirHelpers
    #   - prescription_expired?(resource) - From FhirHelpers
    module OracleHealthRenewabilityHelper
      include RenewalWindow

      # Determines if a medication is renewable.
      # All gate conditions must pass for renewal eligibility.
      #
      # Gate 1: MedicationRequest.status == 'active'
      # Gate 2: Category must be VA Prescription
      # Gate 3: At least one completed dispense exists
      # Gate 4: Validity period end date exists
      # Gate 5: Within 120 days of validity period end
      # Gate 6: Refills exhausted OR prescription expired
      # Gate 7: No active processing
      #
      # @param resource [Hash] FHIR MedicationRequest resource
      # @return [Boolean] true if renewable
      def renewable?(resource)
        return false if resource.nil? || !resource.is_a?(Hash)
        return false unless resource['status'] == 'active'
        return false if non_va_med?(resource)
        return false unless completed_dispense_exists?(resource)
        return false unless validity_period_end_exists?(resource)
        return false unless within_renewal_window?(resource)
        return false unless refills_exhausted_or_expired?(resource)
        return false if active_processing?(resource)

        true
      end

      private

      # Checks if validity period end date exists
      #
      # @param resource [Hash] FHIR MedicationRequest resource
      # @return [Boolean] true if validity period end exists
      def validity_period_end_exists?(resource)
        resource.dig('dispenseRequest', 'validityPeriod', 'end').present?
      end

      # Checks if within renewal window from expiration
      #
      # @param resource [Hash] FHIR MedicationRequest resource
      # @return [Boolean] true if within renewal window
      def within_renewal_window?(resource)
        expiration_date = parse_expiration_date_utc(resource)
        within_renewal_window_days?(expiration_date)
      end

      # Checks if refills exhausted or prescription expired
      # Expired prescriptions are always eligible (within 120-day window).
      # Non-expired prescriptions must have zero refills remaining.
      #
      # @param resource [Hash] FHIR MedicationRequest resource
      # @return [Boolean] true if eligible for renewal
      def refills_exhausted_or_expired?(resource)
        refills_remaining = extract_refill_remaining(resource)
        expired = prescription_expired?(resource)

        expired || refills_remaining.zero?
      end

      # NOTE: prescription_expired? is now provided by FhirHelpers module
      # It checks if the validity period end date is in the past

      # Checks for active processing (web/mobile refill or in-progress dispense)
      #
      # @param resource [Hash] FHIR MedicationRequest resource
      # @return [Boolean] true if active processing detected
      def active_processing?(resource)
        # An expired Rx cannot have genuine active processing: any refill request or in-progress
        # dispense in flight against it will FAIL the OH Work Queue Monitor once processed. Ignoring
        # those signals lets an expired-within-120-days Rx surface under "Renewal needed before
        # refill" instead of being pinned by a doomed in-flight request.
        return false if prescription_expired?(resource)

        return true if refill_requested_via_web_or_mobile?(resource)

        medication_dispenses(resource).any? do |dispense|
          %w[in-progress preparation].include?(dispense['status'])
        end
      end

      # Checks for pending web/mobile refill request
      #
      # @param resource [Hash] FHIR MedicationRequest resource
      # @return [Boolean] true if refill requested via web/mobile
      def refill_requested_via_web_or_mobile?(resource)
        extensions = resource['extension'] || []
        extensions.any? { |ext| ext['url']&.include?('refill-request') && ext['valueBoolean'] == true }
      end
    end
  end
end
