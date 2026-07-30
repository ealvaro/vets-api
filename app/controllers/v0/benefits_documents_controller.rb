# frozen_string_literal: true

require 'lighthouse/benefits_documents/service'
require 'benefits_documents/providers/document_upload_router'

module V0
  class BenefitsDocumentsController < ApplicationController
    before_action { authorize :lighthouse, :access? }

    service_tag 'claims-shared'

    def create
      params.require :file

      # Service expects a different claim ID param
      params[:claim_id] = params[:benefits_claim_id]

      # The frontend may pass a stringified Array of tracked item ids
      # because of the way array values are handled by formData
      if params[:tracked_item_ids].instance_of?(String)
        # Value should look "[123,456]" before it's parsed
        params[:tracked_item_ids] = JSON.parse(params[:tracked_item_ids])
      end

      jid = service.queue_document_upload(params)
      render_job_id(jid)
    end

    private

    def service
      if Flipper.enabled?(:cst_multi_document_provider, @current_user)
        BenefitsDocuments::Providers::DocumentUploadRouter.new(@current_user)
      else
        BenefitsDocuments::Service.new(@current_user)
      end
    end
  end
end
