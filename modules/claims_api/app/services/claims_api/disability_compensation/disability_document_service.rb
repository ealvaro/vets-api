# frozen_string_literal: true

module ClaimsApi
  module DisabilityCompensation
    class DisabilityDocumentService < DocumentServiceBase
      LOG_TAG = '526_v2_Disability_Document_service'

      DOCUMENT_UPLOAD_V1 = 'v1'
      DOCUMENT_UPLOAD_V2 = 'v2'

      DOCUMENT_UPLOAD_SYSTEM_NAMES = {
        DOCUMENT_UPLOAD_V1 => 'Lighthouse',
        DOCUMENT_UPLOAD_V2 => 'VA.gov'
      }.freeze

      def create_upload(claim:, pdf_path:, doc_type: 'L122', original_filename: nil, version: DOCUMENT_UPLOAD_V2)
        unless File.exist? pdf_path
          ClaimsApi::Logger.log('benefits_documents', message: "Error creating upload doc: #{pdf_path} doesn't exist,
                                                      claim_id: #{claim.id}")
          raise Errno::ENOENT, pdf_path
        end

        body = generate_body(claim:, doc_type:, pdf_path:, original_filename:, version:)
        doc_type_name = doc_type == 'L122' ? 'claim' : 'supporting'
        ClaimsApi::BD.new.upload_document(identifier: claim.id, doc_type_name:, body:)
      end

      private

      def document_upload_system_name(version)
        # Normalize the version string to avoid issues with case or whitespace
        key = version.presence.to_s.downcase.strip
        DOCUMENT_UPLOAD_SYSTEM_NAMES.fetch(key) do
          raise ArgumentError, "Unknown document upload version: #{version.inspect}"
        end
      end

      ##
      # Generate form body to upload a document
      #
      # @return {parameters, file}
      def generate_body(claim:, doc_type:, pdf_path:, original_filename: nil, version: DOCUMENT_UPLOAD_V2)
        auth_headers = claim.auth_headers
        veteran_name = compact_name_for_file(auth_headers['va_eauth_firstName'],
                                             auth_headers['va_eauth_lastName'])
        participant_id = auth_headers['va_eauth_pid'].presence
        claim_id = claim.evss_id
        form_name = doc_type == 'L122' ? '526EZ' : 'supporting'
        file_name = generate_file_name(veteran_name:, claim_id:, form_name:, original_filename:)
        tracked_item_ids = claim.tracked_items&.map(&:to_i) if claim&.has_attribute?(:tracked_items)
        system_name = document_upload_system_name(version)

        generate_upload_body(claim_id:, system_name:, doc_type:, pdf_path:, file_name:, birls_file_number: nil,
                             participant_id:, tracked_item_ids:)
      end

      def generate_file_name(veteran_name:, claim_id:, form_name:, original_filename:)
        if form_name == '526EZ'
          build_file_name(veteran_name:, identifier: claim_id, suffix: form_name)
        elsif form_name == 'supporting'
          file_name = get_original_supporting_doc_file_name(original_filename)
          build_file_name(veteran_name:, identifier: claim_id, suffix: file_name)
        end
      end

      ##
      # DisabilityCompensationDocuments method create_unique_filename adds a random 11 digit
      # hex string to the original filename, so we remove that to yield the user-submitted
      # filename to use as part of the filename uploaded to the BD service.
      def get_original_supporting_doc_file_name(original_filename)
        file_extension = File.extname(original_filename)
        base_filename = File.basename(original_filename, file_extension)
        base_filename[0...-12]
      end
    end
  end
end
