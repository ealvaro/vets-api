# frozen_string_literal: true

module Mobile
  module V0
    module Adapters
      class ParticipantDocuments
        # Optionally filter by a Set of normalized document ids (lowercased, braces stripped)
        def self.parse(documents, filter_ids: nil)
          return [] if documents.empty?

          documents.filter_map do |document|
            uuid = document['documentUuid']
            next if filter_ids&.exclude?(uuid.to_s.delete('{}').downcase)

            Mobile::V0::ParticipantDocument.new(
              id: uuid,
              doc_type: document['docTypeId'].to_s,
              type_description: document['documentTypeLabel'],
              received_at: document['receivedAt']
            )
          end
        end
      end
    end
  end
end
