# frozen_string_literal: true

module UnifiedHealthData
  module Adapters
    # Generic FHIR resource parsing and utility methods
    # Shared across different FHIR adapters (MedicationRequest, etc.)
    module FhirHelpers
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

      # @api private
      def first_coding_display(codeable_concept)
        codeable_concept['coding']&.find { |c| c['display'].present? }&.dig('display')
      end
    end
  end
end
