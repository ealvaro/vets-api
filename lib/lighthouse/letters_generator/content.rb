# frozen_string_literal: true

module Lighthouse
  module LettersGenerator
    def self.format_description(letter_type, use_content_format: true)
      if Flipper.enabled?(:cst_letters_description_content_format) && use_content_format
        Content::LETTER_DESCRIPTIONS[letter_type]
      else
        Content::LETTER_DESCRIPTIONS_LEGACY[letter_type]
      end
    end

    module Content
      # Defines the desired order for benefit letters to provide a consistent user experience
      # across all clients (web, mobile, native apps).
      # Note: tsa is appended in vets-api and VA Mobile due to a different code path than other letters
      # TODO: Remove medicare_partd once cst_letters_description_content_format is fully enabled and all clients
      # have migrated to the new description shape.
      LETTER_ORDER = %w[
        benefit_summary
        benefit_verification
        certificate_of_eligibility_home_loan
        proof_of_service
        service_verification
        civil_service
        minimum_essential_coverage
        medicare_partd
        commissary
        foreign_medical_program
      ].freeze

      # Display name overrides for benefit letters to provide consistent naming across all clients.
      # Maps letterType to desired display name. If not present, upstream letterName is used.
      # TODO: Remove medicare_partd once cst_letters_description_content_format is fully enabled and all clients
      # have migrated to the new description shape.
      LETTER_NAME_OVERRIDES = {
        'benefit_summary' => 'Benefits and service summary',
        'benefit_verification' => 'Proof of VA income',
        'certificate_of_eligibility' => 'VA home loan Certificate of Eligibility (COE)',
        'certificate_of_eligibility_home_loan' => 'VA home loan Certificate of Eligibility (COE)',
        'proof_of_service' => 'Proof of service card',
        'service_verification' => 'Service verification',
        'civil_service' => 'Civil service preference',
        'minimum_essential_coverage' => 'Proof of minimum essential coverage',
        'medicare_partd' => 'Creditable prescription drug coverage',
        'commissary' => 'Commissary eligibility',
        'foreign_medical_program' => 'Foreign Medical Program enrollment',
        'tsa' => 'TSA PreCheck application fee waiver'
      }.freeze

      # Letter descriptions for all letter types. Provides structured content for clients to render.
      LETTER_DESCRIPTIONS = YAML.load_file(
        File.join(__dir__, 'descriptions.yml')
      ).freeze

      # Legacy description shape (paragraphs/lists) for clients not yet migrated to the content array format.
      # Remove once cst_letters_description_content_format is fully enabled and all clients are migrated.
      LETTER_DESCRIPTIONS_LEGACY = YAML.load_file(
        File.join(__dir__, 'descriptions_legacy.yml')
      ).freeze
    end
  end
end
