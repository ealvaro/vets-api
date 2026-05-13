# frozen_string_literal: true

require_relative 'date_time_helpers'
require_relative 'fhir_helpers'

module UnifiedHealthData
  module Adapters
    # Medication-dispense-specific FHIR helpers for prescriptions.
    # Used by OracleHealthPrescriptionAdapter and its helper concerns.
    module MedicationDispenseHelpers
      include DateTimeHelpers
      include FhirHelpers

      # Extracts NDC (National Drug Code) from FHIR MedicationDispense
      #
      # @param dispense [Hash] FHIR MedicationDispense resource
      # @return [String, nil] NDC code or nil if not found
      def extract_ndc_number(dispense)
        coding = dispense.dig('medicationCodeableConcept', 'coding') || []
        ndc_coding = coding.find { |c| c['system'] == 'http://hl7.org/fhir/sid/ndc' }
        ndc_coding&.dig('code')
      end

      # Extracts MedicationDispense resources from a MedicationRequest resource
      #
      # @param medication_request [Hash] FHIR MedicationRequest resource
      # @return [Array<Hash>] Array of MedicationDispense resources
      def medication_dispenses(medication_request)
        return [] if medication_request.nil?

        (medication_request['contained'] || []).select { |r| r['resourceType'] == 'MedicationDispense' }
      end

      # Finds the most recent MedicationDispense from contained resources
      # Sorted by whenHandedOver or whenPrepared date
      #
      # @param medication_request [Hash] FHIR MedicationRequest resource
      # @return [Hash, nil] Most recent MedicationDispense or nil if none found
      def find_most_recent_medication_dispense(medication_request)
        dispenses = medication_dispenses(medication_request)
        return nil if dispenses.empty?

        dispenses.max_by do |dispense|
          date = dispense['whenHandedOver'] || dispense['whenPrepared']
          date ? parse_date_or_epoch(date) : Time.zone.at(0)
        end
      end

      # Checks for at least one successfully completed dispense.
      # Dispenses with status 'entered-in-error' represent voided records and
      # do not count as evidence that the initial fill was processed.
      #
      # @param resource [Hash] FHIR MedicationRequest resource
      # @return [Boolean] true when a completed MedicationDispense exists
      def completed_dispense_exists?(resource)
        medication_dispenses(resource).any? { |dispense| dispense['status'] == 'completed' }
      end

      # Builds instruction text from FHIR dosageInstruction components
      #
      # @param instruction [Hash] FHIR dosageInstruction object
      # @return [String] Formatted instruction text
      def build_instruction_text(instruction)
        parts = []
        parts << instruction.dig('timing', 'code', 'text') if instruction.dig('timing', 'code', 'text')
        parts << instruction.dig('route', 'text') if instruction.dig('route', 'text')

        dose_and_rate = instruction.dig('doseAndRate', 0)
        if dose_and_rate
          dose_quantity = dose_and_rate.dig('doseQuantity', 'value')
          dose_unit = dose_and_rate.dig('doseQuantity', 'unit')
          parts << "#{dose_quantity} #{dose_unit}" if dose_quantity
        end

        parts.join(' ')
      end

      # Parses expiration date from FHIR MedicationRequest to UTC Time
      # Oracle Health dates are in Zulu time (UTC)
      #
      # @param resource [Hash] FHIR MedicationRequest resource
      # @return [Time, nil] Parsed UTC time or nil if not available/invalid
      def parse_expiration_date_utc(resource)
        expiration_string = resource.dig('dispenseRequest', 'validityPeriod', 'end')
        return nil if expiration_string.blank?

        parsed_time = Time.zone.parse(expiration_string)
        unless parsed_time
          Rails.logger.warn("Invalid expiration date for prescription #{resource['id']}: #{expiration_string}")
          return nil
        end

        parsed_time.utc
      rescue ArgumentError => e
        Rails.logger.warn("Failed to parse expiration date '#{expiration_string}': #{e.message}")
        nil
      end

      # Checks if prescription validity period has ended
      #
      # @param resource [Hash] FHIR MedicationRequest resource
      # @return [Boolean] true if expired (validity period end is in the past)
      def prescription_expired?(resource)
        (expiration = parse_expiration_date_utc(resource)) ? expiration < Time.current.utc : false
      end

      # Extracts SIG (dosage instructions) from FHIR MedicationDispense
      # Concatenates all dosageInstruction texts
      #
      # @param dispense [Hash] FHIR MedicationDispense resource
      # @return [String, nil] Concatenated dosage instructions or nil if none
      def extract_sig_from_dispense(dispense)
        dosage_instructions = dispense['dosageInstruction'] || []
        return nil if dosage_instructions.empty?

        texts = dosage_instructions.filter_map { |i| i['text'] if i.is_a?(Hash) }
        texts.presence&.join(' ')
      end
    end
  end
end
