# frozen_string_literal: true

module BenefitsDocuments
  module Providers
    # Interface contract for document upload providers.
    module BenefitsDocumentsProvider
      # Queues a document upload for the selected provider.
      #
      # @param _params [ActionController::Parameters, Hash]
      # @return [Hash, String] Provider-defined job identifier payload
      def queue_document_upload(_params) = raise(NotImplementedError)
    end
  end
end
