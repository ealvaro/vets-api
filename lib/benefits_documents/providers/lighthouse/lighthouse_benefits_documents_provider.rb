# frozen_string_literal: true

require 'benefits_documents/providers/benefits_documents_provider'
require 'lighthouse/benefits_documents/service'

module BenefitsDocuments
  module Providers
    module Lighthouse
      class LighthouseBenefitsDocumentsProvider
        include BenefitsDocuments::Providers::BenefitsDocumentsProvider
        delegate :queue_document_upload, to: :service

        def initialize(current_user)
          @service = BenefitsDocuments::Service.new(current_user)
        end

        private

        attr_reader :service
      end
    end
  end
end
