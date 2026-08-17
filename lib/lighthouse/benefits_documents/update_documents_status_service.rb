# frozen_string_literal: true

require 'lighthouse/benefits_documents/documents_status_polling_service'
require 'lighthouse/benefits_documents/upload_status_updater'

module BenefitsDocuments
  class UpdateDocumentsStatusService
    def self.call(*)
      new(*).process_status_updates
    end

    # @param pending_evidence_submission_batch - EvidenceSubmission records with a upload_status of PENDING
    # EvidenceSubmission records polled for status updates on Lighthouse's '/uploads/status' endpoint
    # @param lighthouse_status_response [Hash] the parsed JSON response body from the endpoint
    def initialize(pending_evidence_submission_batch, lighthouse_status_response)
      @pending_evidence_submission_batch = pending_evidence_submission_batch
      @lighthouse_status_response = lighthouse_status_response
    end

    def process_status_updates
      update_documents_status
      unknown_ids = @lighthouse_status_response.dig('data', 'requestIdsNotFound')

      return { success: true } if unknown_ids.blank?

      Rails.logger.warn(
        'Benefits Documents API cannot find these requestIds and cannot verify upload status', {
          request_ids: unknown_ids
        }
      )
      { success: false, response: { status: 404, body: 'Upload Request Async Status Not Found', unknown_ids: } }
    end

    private

    # Loop through each status response that lighthouse returned and use the request Id in the status response to
    # find the given PENDING evidence submission record. Then we call BenefitsDocuments::UploadStatusUpdater
    # to update the PENDING evidence submission record accordingly.
    def update_documents_status
      submissions_by_request_id = @pending_evidence_submission_batch.index_by { |s| s.request_id.to_s }

      @lighthouse_status_response.dig('data', 'statuses').each do |status_response|
        pending_evidence_submission = submissions_by_request_id[status_response['requestId'].to_s]

        unless pending_evidence_submission
          Rails.logger.error(
            'BenefitsDocuments::UpdateDocumentsStatusService could not find EvidenceSubmission for request_id',
            { request_id: status_response['requestId'] }
          )
          StatsD.increment('worker.lighthouse.cst_document_uploads.evidence_submission_update_error')
          next
        end

        BenefitsDocuments::UploadStatusUpdater.call(status_response, pending_evidence_submission)
      rescue => e
        Rails.logger.error(
          'BenefitsDocuments::UpdateDocumentsStatusService failed to update EvidenceSubmission for request_id',
          { request_id: status_response['requestId'], error_class: e.class.name, error: e.message }
        )
        StatsD.increment('worker.lighthouse.cst_document_uploads.evidence_submission_update_error')
      end
    end
  end
end
