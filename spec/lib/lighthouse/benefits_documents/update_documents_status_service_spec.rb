# frozen_string_literal: true

require 'rails_helper'
require 'lighthouse/benefits_documents/update_documents_status_service'
require 'lighthouse/benefits_documents/documents_status_polling_service'

RSpec.describe BenefitsDocuments::UpdateDocumentsStatusService do
  describe '#call' do
    let(:lighthouse_document_upload1) do
      create(:bd_evidence_submission_pending, request_id: 1, job_class: 'BenefitsDocuments::Service')
    end
    let(:lighthouse_document_upload2) do
      create(:bd_evidence_submission_pending, request_id: 2, job_class: 'BenefitsDocuments::Service')
    end
    let(:lighthouse_document_upload3) do
      create(:bd_evidence_submission_pending, request_id: 3, job_class: 'BenefitsDocuments::Service')
    end

    let :pending_evidence_submission_ids do
      [
        lighthouse_document_upload1.request_id,
        lighthouse_document_upload2.request_id,
        lighthouse_document_upload3.request_id
      ]
    end
    let(:pending_evidence_submission_batch) do
      EvidenceSubmission.where(request_id: pending_evidence_submission_ids)
    end

    describe 'process_status_updates' do
      before do
        allow(Rails.logger).to receive(:warn)
      end

      let(:lighthouse_status_response) do
        {
          'data' => {
            'statuses' => [
              {
                'requestId' => lighthouse_document_upload1.request_id,
                'status' => BenefitsDocuments::Constants::UPLOAD_STATUS[:SUCCESS],
                'error' => nil
              },
              {
                'requestId' => lighthouse_document_upload2.request_id,
                'status' => BenefitsDocuments::Constants::UPLOAD_STATUS[:FAILED],
                'error' => 'ERROR'
              },
              {
                'requestId' => lighthouse_document_upload3.request_id,
                'status' => BenefitsDocuments::Constants::UPLOAD_STATUS[:PENDING],
                'error' => nil
              }
            ],
            'requestIdsNotFound' => ['1234']
          }
        }
      end

      it 'updates the status of 2 records to FAILED and SUCCESS and leaves one in PENDING' do
        expect(lighthouse_document_upload1.upload_status).to eq(BenefitsDocuments::Constants::UPLOAD_STATUS[:PENDING])
        expect(lighthouse_document_upload2.upload_status).to eq(BenefitsDocuments::Constants::UPLOAD_STATUS[:PENDING])
        expect(lighthouse_document_upload3.upload_status).to eq(BenefitsDocuments::Constants::UPLOAD_STATUS[:PENDING])

        described_class.call(pending_evidence_submission_batch, lighthouse_status_response)

        es1 = EvidenceSubmission.find_by(request_id: lighthouse_document_upload1.request_id)
        es2 = EvidenceSubmission.find_by(request_id: lighthouse_document_upload2.request_id)
        es3 = EvidenceSubmission.find_by(request_id: lighthouse_document_upload3.request_id)
        expect(es1.upload_status).to eq(BenefitsDocuments::Constants::UPLOAD_STATUS[:SUCCESS])
        expect(es1.delete_date).not_to be_nil
        expect(es2.upload_status).to eq(BenefitsDocuments::Constants::UPLOAD_STATUS[:FAILED])
        expect(es2.failed_date).not_to be_nil
        expect(es2.acknowledgement_date).not_to be_nil
        expect(es2.error_message).to eq('ERROR')
        expect(es3.upload_status).to eq(BenefitsDocuments::Constants::UPLOAD_STATUS[:PENDING])
      end

      it 'logs when requestIds aren\'t found' do
        described_class.call(pending_evidence_submission_batch, lighthouse_status_response)
        expect(Rails.logger).to have_received(:warn).with(
          'Benefits Documents API cannot find these requestIds and cannot verify upload status',
          { request_ids: ['1234'] }
        )
      end
    end

    describe 'when a status response requestId does not match any record in the batch' do
      before do
        allow(Rails.logger).to receive(:error)
        allow(StatsD).to receive(:increment)
      end

      let(:unmatched_request_id) { 999 }
      let(:lighthouse_status_response) do
        {
          'data' => {
            'statuses' => [
              {
                'requestId' => unmatched_request_id,
                'status' => BenefitsDocuments::Constants::UPLOAD_STATUS[:FAILED],
                'error' => 'ERROR'
              },
              {
                'requestId' => lighthouse_document_upload1.request_id,
                'status' => BenefitsDocuments::Constants::UPLOAD_STATUS[:SUCCESS],
                'error' => nil
              }
            ]
          }
        }
      end

      it 'rescues the RecordNotFound, logs, increments a metric, and still processes the remaining statuses' do
        described_class.call(pending_evidence_submission_batch, lighthouse_status_response)

        expect(Rails.logger).to have_received(:error).with(
          'BenefitsDocuments::UpdateDocumentsStatusService could not find EvidenceSubmission for request_id',
          { request_id: unmatched_request_id }
        )
        expect(StatsD).to have_received(:increment).with(
          'worker.lighthouse.cst_document_uploads.evidence_submission_update_error'
        )

        es1 = EvidenceSubmission.find_by(request_id: lighthouse_document_upload1.request_id)
        expect(es1.upload_status).to eq(BenefitsDocuments::Constants::UPLOAD_STATUS[:SUCCESS])
      end
    end

    describe 'when UploadStatusUpdater raises an error unrelated to a missing record' do
      before do
        allow(Rails.logger).to receive(:error)
        allow(StatsD).to receive(:increment)
        allow(BenefitsDocuments::UploadStatusUpdater).to receive(:call).and_call_original
        allow(BenefitsDocuments::UploadStatusUpdater).to receive(:call)
          .with(hash_including('requestId' => lighthouse_document_upload1.request_id), anything)
          .and_raise(JSON::ParserError, 'unexpected token')
      end

      let(:lighthouse_status_response) do
        {
          'data' => {
            'statuses' => [
              {
                'requestId' => lighthouse_document_upload1.request_id,
                'status' => BenefitsDocuments::Constants::UPLOAD_STATUS[:FAILED],
                'error' => 'ERROR'
              },
              {
                'requestId' => lighthouse_document_upload2.request_id,
                'status' => BenefitsDocuments::Constants::UPLOAD_STATUS[:SUCCESS],
                'error' => nil
              }
            ]
          }
        }
      end

      it 'rescues the error, logs, increments a metric, and still processes the remaining statuses' do
        described_class.call(pending_evidence_submission_batch, lighthouse_status_response)

        expect(Rails.logger).to have_received(:error).with(
          'BenefitsDocuments::UpdateDocumentsStatusService failed to update EvidenceSubmission for request_id',
          {
            request_id: lighthouse_document_upload1.request_id,
            error_class: 'JSON::ParserError',
            error: 'unexpected token'
          }
        )
        expect(StatsD).to have_received(:increment).with(
          'worker.lighthouse.cst_document_uploads.evidence_submission_update_error'
        )

        es2 = EvidenceSubmission.find_by(request_id: lighthouse_document_upload2.request_id)
        expect(es2.upload_status).to eq(BenefitsDocuments::Constants::UPLOAD_STATUS[:SUCCESS])
      end
    end
  end
end
