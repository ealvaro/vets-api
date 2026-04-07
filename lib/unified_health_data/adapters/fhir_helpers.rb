# frozen_string_literal: true

module UnifiedHealthData
  module Adapters
    # Generic FHIR resource parsing and utility methods
    # Shared across different FHIR adapters (MedicationRequest, etc.)
    module FhirHelpers
      # Parses a date string or returns epoch if invalid/missing
      #
      # @param date_string [String, nil] Date string to parse
      # @return [Time] Parsed time or epoch
      def parse_date_or_epoch(date_string)
        return Time.zone.at(0) unless date_string

        parsed_time = Time.zone.parse(date_string)
        parsed_time || Time.zone.at(0)
      rescue ArgumentError, TypeError
        Time.zone.at(0)
      end

      # Calculates days since a given date
      #
      # @param date_string [String] ISO 8601 date string
      # @return [Integer, nil] Days since the date or nil if invalid
      def days_since(date_string)
        return nil unless date_string

        submit_time = Time.zone.parse(date_string)
        return nil unless submit_time

        days = ((Time.zone.now - submit_time) / 1.day).floor
        days >= 0 ? days : nil
      rescue ArgumentError, TypeError
        nil
      end

      # Finds a FHIR identifier value by type text
      #
      # @param identifiers [Array<Hash>] Array of FHIR identifier objects
      # @param type_text [String] The type.text value to search for
      # @return [String, nil] The identifier value or nil if not found
      def find_identifier_value(identifiers, type_text)
        identifiers.find { |id| id.dig('type', 'text') == type_text }&.dig('value')
      end

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

      # Extracts a display string from a FHIR CodeableConcept.
      #
      # By default, prefers `text` (FHIR-recommended human-readable summary),
      # falling back to the first `coding[].display`. Pass `prefer: :coding`
      # to reverse the priority (useful when the structured code display is
      # preferred over free-text, e.g. for body sites or category codes).
      #
      # @param codeable_concept [Hash, nil] A FHIR CodeableConcept hash
      # @param prefer [Symbol] :text (default) or :coding
      # @return [String, nil] The display string, or nil if none found
      def extract_codeable_concept_display(codeable_concept, prefer: :text)
        return nil if codeable_concept.nil?

        case prefer.to_sym
        when :coding
          first_coding_display(codeable_concept) || codeable_concept['text'].presence
        else
          codeable_concept['text'].presence || first_coding_display(codeable_concept)
        end
      end

      # Normalizes a date to noon UTC of the intended calendar date.
      # VistA encodes expiration as midnight Eastern (start of day) and Oracle Health
      # as 23:59:59 local→UTC — both can produce a UTC date that differs from the
      # intended local date. Noon UTC falls on the same calendar date in every US
      # timezone (UTC-11 Samoa through UTC+10 Guam), preventing off-by-one errors.
      #
      # @param date_string [String] ISO 8601 or RFC 2822 date string
      # @param timezone [String] IANA timezone for interpreting the date
      # @return [String, nil] "YYYY-MM-DDT12:00:00.000Z" or nil if invalid
      def normalize_date_to_noon_utc(date_string, timezone)
        return nil if date_string.blank? || timezone.blank?

        zone = Time.find_zone(timezone)
        return log_unknown_timezone(date_string, timezone) unless zone

        parsed = zone.parse(date_string)
        return nil unless parsed

        local_date = parsed.to_date
        Time.utc(local_date.year, local_date.month, local_date.day, 12, 0, 0).iso8601(3)
      rescue ArgumentError => e
        Rails.logger.warn("Failed to normalize date '#{date_string}' in timezone '#{timezone}': #{e.message}")
        nil
      end

      # @api private
      def log_unknown_timezone(date_string, timezone)
        Rails.logger.warn("Unknown timezone '#{timezone}' when normalizing date '#{date_string}'")
        nil
      end

      # @api private
      def first_coding_display(codeable_concept)
        codeable_concept['coding']&.find { |c| c['display'].present? }&.dig('display')
      end
    end
  end
end
