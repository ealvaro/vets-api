# frozen_string_literal: true

require 'lighthouse/benefits_documents/service'

module Mobile
  module V0
    class EfolderController < ApplicationController
      MAX_PAGE_SIZE = 100

      def index
        documents = if Flipper.enabled?(:efolder_use_lighthouse_benefits_documents_service, @current_user)
                      raw_documents = retrieve_all_documents
                      participant_documents_adapter.parse(raw_documents)
                    else
                      response = service.list_documents
                      efolder_adapter.parse(response)
                    end

        render json: Mobile::V0::EfolderSerializer.new(documents)
      rescue VBMS::FilenumberDoesNotExist
        raise_vbms_bad_gateway('VBMS failed to resolve file number')
      rescue VBMS::DocumentTooBig
        raise_vbms_bad_gateway('VBMS document request exceeded size limit')
      rescue VBMS::HTTPError
        raise_vbms_bad_gateway('VBMS service error')
      rescue Common::Exceptions::ExternalServerInternalServerError => e
        raise Common::Exceptions::BadGateway.new(detail: e.message)
      end

      def search
        raw_documents = retrieve_all_documents
        documents = participant_documents_adapter.parse(raw_documents, filter_ids: requested_document_ids)

        render json: Mobile::V0::EfolderSerializer.new(documents)
      rescue Common::Exceptions::ExternalServerInternalServerError => e
        raise Common::Exceptions::BadGateway.new(detail: e.message)
      end

      def download
        document = if Flipper.enabled?(:efolder_use_lighthouse_benefits_documents_service, @current_user)
                     # Backwards Compatibility: Delete {} brackets from document id as the
                     # benefit documents service doesn't support them
                     sanitized_id = params[:document_id].delete('{}')
                     verify_document_belongs_to_user!(sanitized_id)
                     lighthouse_document_service
                       .participant_documents_download(document_uuid: sanitized_id,
                                                       participant_id: @current_user.participant_id).body
                   else
                     service.get_document(params[:document_id])
                   end

        send_data(
          document,
          type: 'application/pdf',
          filename: file_name
        )
      rescue VBMS::FilenumberDoesNotExist
        raise_vbms_bad_gateway('VBMS failed to resolve file number')
      rescue VBMS::DocumentTooBig
        raise_vbms_bad_gateway('VBMS document request exceeded size limit')
      rescue VBMS::HTTPError
        raise_vbms_bad_gateway('VBMS service error')
      end

      private

      # Verify that the requested document actually belongs to the authenticated user.
      # Without this check an attacker who knows (or guesses) a document UUID can download
      # another veteran's eFolder documents (IDOR). The web eFolder controller in
      # lib/efolder/service.rb already performs this check via verify_document_in_folder;
      # the mobile controller was missing it for the Lighthouse path.
      def verify_document_belongs_to_user!(document_uuid)
        authorized_ids = retrieve_all_documents.to_set { |doc| normalize_id(doc['documentUuid']) }
        normalized_request_id = normalize_id(document_uuid)
        return if authorized_ids.include?(normalized_request_id)

        raise Common::Exceptions::RecordNotFound, document_uuid
      end

      def requested_document_ids
        requested = params.permit(documents: %i[document_id filename]).fetch(:documents, [])
        requested.filter_map { |doc| normalize_id(doc[:document_id]) }.to_set
      end

      def normalize_id(id)
        id.to_s.delete('{}').downcase
      end

      def retrieve_all_documents
        all_documents = []
        page_number = 1
        has_more = true

        while has_more
          response = lighthouse_document_service.participant_documents_search(
            participant_id: @current_user.participant_id, page_number:, page_size: MAX_PAGE_SIZE
          ).body

          # Benefits Documents Service will pass back an empty data object if user has no documents
          break if response['data'].empty?

          documents = response.dig('data', 'documents')
          all_documents.concat(documents)

          if documents.size < MAX_PAGE_SIZE
            has_more = false
          else
            page_number += 1
          end
        end

        all_documents
      end

      def service
        ::Efolder::Service.new(@current_user)
      end

      def lighthouse_document_service
        @lighthouse_document_service ||= BenefitsDocuments::Service.new(@current_user)
      end

      def file_name
        params.require(:file_name)
      end

      def efolder_adapter
        Mobile::V0::Adapters::Efolder
      end

      def participant_documents_adapter
        Mobile::V0::Adapters::ParticipantDocuments
      end

      # Maps VBMS upstream errors to 502 Bad Gateway so they don't surface as 500s.
      # VBMS::HTTPError subclasses (FilenumberDoesNotExist, DocumentTooBig, DownForMaintenance, etc.)
      # all indicate an upstream VBMS failure, not an application bug.
      def raise_vbms_bad_gateway(detail)
        error = Common::Exceptions::SerializableError.new(
          status: '502',
          title: 'Bad Gateway',
          detail:,
          code: '502'
        )
        raise Common::Exceptions::BadGateway.new(errors: [error])
      end
    end
  end
end
