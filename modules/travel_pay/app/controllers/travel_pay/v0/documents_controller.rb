# frozen_string_literal: true

module TravelPay
  module V0
    class DocumentsController < ApplicationController
      include FeatureFlagHelper
      include IdValidation
      include ErrorHandling

      before_action :check_feature_flag, only: %i[create destroy]

      def show
        document_data = service.download_document(params[:claim_id], params[:id])

        send_data(
          document_data[:body],
          type: document_data[:type],
          disposition: document_data[:disposition],
          filename: document_data[:filename]
        )
      end

      def create
        claim_id = params[:claim_id]
        document = params[:document] || params[:Document] # accept capital D from API

        validate_uuid_exists!(claim_id, 'Claim')
        validate_document_exists!(document)

        Rails.logger.info(
          message: "Creating attachment for claim #{claim_id.slice(0, 8)}"
        )
        response_data = service.upload_document(claim_id, document)
        increment_create_statsd(document, 'success')
        render json: { documentId: response_data['documentId'] }, status: :created
      rescue
        increment_create_statsd(document, 'failure')
        raise
      end

      def destroy
        claim_id = params[:claim_id]
        document_id = params[:id]

        validate_uuid_exists!(claim_id, 'Claim')
        validate_uuid_exists!(document_id, 'Document')
        # TODO: do we need to verify that the document id is an actual id that exists?

        response_data = service.delete_document(claim_id, document_id)
        render json: { documentId: response_data['documentId'] }, status: :ok
      end

      private

      def check_feature_flag
        verify_feature_flag!(
          :travel_pay_enable_complex_claims,
          current_user,
          error_message: 'Travel Pay document endpoint unavailable per feature toggle'
        )
      end

      def increment_create_statsd(document, result)
        document_type = File.basename(document&.original_filename.to_s, '.*') == 'proof-of-attendance' ? 'poa' : 'other'

        StatsD.increment('travel_pay.documents.create',
                         tags: ["document_type:#{document_type}",
                                "result:#{result}"])
      end

      def auth_manager
        @auth_manager ||= TravelPay::AuthManager.new(Settings.travel_pay.client_number, @current_user)
      end

      def service
        @service ||= TravelPay::DocumentsService.new(auth_manager)
      end

      def validate_document_exists!(document)
        return if document.present?

        raise Common::Exceptions::BadRequest.new(detail: 'Document is required')
      end
    end
  end
end
