# frozen_string_literal: true

require 'mms/attachments'
require 'mms/data_formatting'

module SurvivorsBenefits
  # Namespace for BPDS-facing classes for the 21P-534EZ Survivors Benefits form.
  module BPDS
    # Formatter that transforms a 21P-534EZ SavedClaim's parsed form data into the BPDS
    # submission built by BPDS::Sidekiq::SubmitToBPDSJob.
    #
    # #format returns the structured data the claim already generates
    # (SurvivorsBenefits::StructuredData, versioned to match the active form) and becomes the
    # BPDS envelope's `payload`. #attachments returns the supporting documents, which the
    # service places alongside `payload` in the envelope (not inside it). This is intentionally
    # separate from the IBM/MMS payload built by SurvivorsBenefits::SavedClaim#to_ibm: MMS does
    # not accept attachment data, whereas BPDS does. Each attachment entry combines the upload
    # metadata with the CAVE-extracted structured data parsed from the file's idpArtifacts by
    # Mms::Attachments.
    class Formatter
      include Mms::DataFormatting

      # @param parsed_form [Hash] The claim's parsed form data
      def initialize(parsed_form)
        @form = parsed_form || {}
      end

      # @return [Hash] The claim's structured data (the BPDS envelope `payload`).
      def format
        structured_data
      end

      # @return [Array<Hash>, nil] One entry per uploaded file (upload metadata + CAVE-extracted
      #   structured data), or nil when there are no files. Placed alongside `payload` in the
      #   BPDS envelope.
      def attachments
        files = Array(@form['files'])
        return nil if files.empty?

        structured_by_code = attachment_structured_data_by_code
        files.each_with_index.map do |file, index|
          entry = attachment_metadata(file, index)
          structured = structured_by_code[file['confirmationCode']]
          entry['structuredData'] = structured if structured.present?
          entry
        end
      end

      private

      # Builds the structured data payload with the same versioned service the claim
      # uses for IBM/MMS transmission, so BPDS mirrors the form version in play.
      # @return [Hash]
      def structured_data
        structured_data_service_class.new(@form).build_structured_data
      end

      # Selects the structured data service for the active form version, matching
      # SurvivorsBenefits::SavedClaim#to_ibm.
      # @return [Class]
      def structured_data_service_class
        if Flipper.enabled?(:survivors_benefits_form_2025_version_enabled)
          SurvivorsBenefits::StructuredData::V2025::StructuredDataService
        else
          SurvivorsBenefits::StructuredData::V2022::StructuredDataService
        end
      end

      # Upload metadata for a single file, populated by the SurvivorsBenefits SavedClaim
      # from PersistentAttachment uploads. nil values are dropped.
      # @return [Hash]
      def attachment_metadata(file, index)
        {
          'index' => index + 1,
          'confirmationCode' => file['confirmationCode'],
          'name' => file['name'],
          'size' => file['size'],
          'type' => file['type']
        }.compact
      end

      # Parses the form's files through Mms::Attachments and indexes the resulting
      # CAVE-extracted structured data (transform_data) by confirmationCode. Only
      # CAVE-validated files (those carrying idpArtifacts) yield an entry. Nil values are
      # normalized to empty strings, matching how the flat structured data is delivered.
      # @return [Hash{String => Hash}]
      def attachment_structured_data_by_code
        Mms::Attachments::Service.new(Array(@form['files'])).files.each_value.with_object({}) do |attached_file, acc|
          next unless attached_file&.form_data

          acc[attached_file.confirmation_code] = transform_nils_to_empty_strings(attached_file.form_data)
        end
      end
    end
  end
end
