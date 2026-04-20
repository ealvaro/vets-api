# frozen_string_literal: true

# Service that accepts a list of documents and a file number, and filters out
# any VA documents by cross-referencing with the claim letters search endpoint of the Benefits Documents API
module ClaimsApi
  module FilterVADocumentsConcern
    extend ActiveSupport::Concern

    # assumption is that documents and identifier have already been validated before this method is called
    # to prevent unnecessary API calls and processing
    # the identifier can be either a file number or participant id, and the method will handle both cases
    def filter_va_documents(documents, file_number: nil, participant_id: nil)
      # Get VA claim letters (claim_letters_search only returns VA-generated documents)
      va_docs = benefits_doc_api.claim_letters_search(file_number:, participant_id:)&.dig(:data, :documents) || []

      va_document_ids = va_docs.map do |va_doc|
        # Support both symbol and string keys for documentUuid
        doc_hash = va_doc.respond_to?(:with_indifferent_access) ? va_doc.with_indifferent_access : va_doc
        raw_uuid = doc_hash[:documentUuid] || doc_hash['documentUuid']
        normalize_document_uuid(raw_uuid) if raw_uuid.present?
      end.compact.to_set

      documents.reject do |doc|
        doc_hash = doc.respond_to?(:with_indifferent_access) ? doc.with_indifferent_access : doc
        raw_uuid = doc_hash[:documentUuid] || doc_hash['documentUuid']
        next if raw_uuid.blank?

        va_document_ids.include?(normalize_document_uuid(raw_uuid))
      end
    end

    private

    def normalize_document_uuid(document_uuid)
      document_uuid.to_s.downcase.gsub(/[{}]/, '')
    end
  end
end
