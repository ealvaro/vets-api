# frozen_string_literal: true

module SurvivorsBenefits
  # Namespace for BPDS-facing classes for the 21P-534EZ Survivors Benefits form.
  module BPDS
    # Formatter that transforms a 21P-534EZ SavedClaim's parsed form data into the
    # structured payload delivered to BPDS by BPDS::Sidekiq::SubmitToBPDSJob.
    #
    # 21P-534EZ is the first BIO form on the BPDS path. Until the BPDS team publishes
    # a 534EZ schema, this formatter passes the parsed form through and surfaces
    # attachment metadata from the form's `files` key. Follow-up work will replace
    # the passthrough with field-by-field mapping to the published schema.
    class Formatter
      # @param parsed_form [Hash] The claim's parsed form data
      def initialize(parsed_form)
        @form = parsed_form || {}
      end

      # @return [Hash] BPDS payload
      def format
        payload = @form.dup
        attachments = attachment_metadata
        payload['attachments'] = attachments if attachments.present?
        payload
      end

      private

      # Extracts attachment metadata from the form's `files` key, which the
      # SurvivorsBenefits SavedClaim populates from PersistentAttachment uploads.
      # Each file carries confirmationCode, name, size, and (when CAVE-validated)
      # idpArtifacts.
      def attachment_metadata
        files = Array(@form['files'])
        return nil if files.empty?

        files.each_with_index.map do |file, index|
          {
            'index' => index + 1,
            'confirmationCode' => file['confirmationCode'],
            'name' => file['name'],
            'size' => file['size'],
            'type' => file['type']
          }.compact
        end
      end
    end
  end
end
