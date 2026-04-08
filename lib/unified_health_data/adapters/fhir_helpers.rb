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

      # Finds a FHIR identifier value by type text
      #
      # @param identifiers [Array<Hash>] Array of FHIR identifier objects
      # @param type_text [String] The type.text value to search for
      # @return [String, nil] The identifier value or nil if not found
      def find_identifier_value(identifiers, type_text)
        identifiers.find { |id| id.dig('type', 'text') == type_text }&.dig('value')
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
    end # rubocop:enable Metrics/ModuleLength
  end
end
