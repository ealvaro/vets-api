# frozen_string_literal: true

module BenefitsDocuments
  module Providers
    class ClaimOwnershipResolver
      DEFAULT_PROVIDER = :lighthouse
      SUPPORTED_PROVIDERS = %i[lighthouse ivc_champva].freeze

      def provider_for(params)
        explicit_provider(params) || champva_provider(params) || DEFAULT_PROVIDER
      end

      private

      def explicit_provider(params)
        provider = params[:provider].presence&.to_sym
        return provider if SUPPORTED_PROVIDERS.include?(provider)

        upload_destination_provider(params)
      end

      def upload_destination_provider(params)
        upload_destination_key = params.dig(:upload_metadata, :upload_destination_key).presence ||
                                 params.dig(:uploadMetadata, :uploadDestinationKey).presence

        case upload_destination_key
        when 'ivc_champva_supporting_documents'
          :ivc_champva
        when 'benefits_claims'
          :lighthouse
        end
      end

      def champva_provider(params)
        claim_id = params[:claim_id].presence || params[:benefits_claim_id].presence
        return if claim_id.blank? || claim_id.to_s.match?(/\A\d+\z/)

        :ivc_champva if IvcChampvaForm.exists?(form_uuid: claim_id.to_s)
      end
    end
  end
end
