# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Form21aDocumentSubmissionAttempt, type: :model do
  let(:submission) do
    Form21aDocumentSubmission.create!(
      form_id: '21a',
      application_id: 12_345,
      form21a_attachment_guid: SecureRandom.uuid,
      document_type: '1',
      content_type: 'application/pdf'
    )
  end

  describe 'associations' do
    it 'belongs to a form 21a document submission' do
      association = described_class.reflect_on_association(:submission)

      expect(association.macro).to eq(:belongs_to)
      expect(association.class_name).to eq('Form21aDocumentSubmission')
      expect(association.foreign_key).to eq('form21a_document_submission_id')
      expect(association.options[:inverse_of]).to eq(:submission_attempts)
    end
  end

  describe 'enums' do
    it 'defines the expected status values' do
      expect(described_class.statuses).to eq(
        'pending' => 'pending',
        'uploading' => 'uploading',
        'succeeded' => 'succeeded',
        'failed_transient' => 'failed_transient',
        'failed_permanent' => 'failed_permanent',
        'abandoned' => 'abandoned'
      )
    end

    it 'defines the expected failure_classification values' do
      expect(described_class.failure_classifications).to eq(
        'transient' => 'transient',
        'permanent' => 'permanent'
      )
    end
  end

  describe 'defaults' do
    it 'defaults status to pending' do
      attempt = described_class.create!(submission:)

      expect(attempt.status).to eq('pending')
      expect(attempt).to be_status_pending
    end
  end

  describe 'encrypted fields' do
    it 'stores and retrieves metadata through encrypted metadata_ciphertext' do
      metadata = {
        'error_class' => 'Faraday::TimeoutError',
        'job_class' => 'AccreditedRepresentativePortal::UploadForm21aDocumentToGCLAWSJob'
      }

      attempt = described_class.create!(
        submission:,
        status: 'failed_transient',
        failure_classification: 'transient',
        last_http_status: 500,
        metadata:
      )

      attempt.reload

      expect(attempt.metadata).to eq(metadata)
      expect(attempt.metadata_ciphertext).to be_present
      expect(attempt.metadata_ciphertext.to_s).not_to include('Faraday::TimeoutError')
    end

    it 'stores and retrieves error_message through encrypted error_message_ciphertext' do
      error_message = 'GCLAWS Document API returned 500'

      attempt = described_class.create!(
        submission:,
        status: 'failed_transient',
        failure_classification: 'transient',
        last_http_status: 500,
        error_message:
      )

      attempt.reload

      expect(attempt.error_message).to eq(error_message)
      expect(attempt.error_message_ciphertext).to be_present
      expect(attempt.error_message_ciphertext.to_s).not_to include(error_message)
    end

    it 'stores and retrieves response through encrypted response_ciphertext' do
      response = {
        'status' => 500,
        'body' => 'Internal Server Error'
      }

      attempt = described_class.create!(
        submission:,
        status: 'failed_transient',
        failure_classification: 'transient',
        last_http_status: 500,
        response:
      )

      attempt.reload

      expect(attempt.response).to eq(response)
      expect(attempt.response_ciphertext).to be_present
      expect(attempt.response_ciphertext.to_s).not_to include('Internal Server Error')
    end
  end

  describe 'status propagation' do
    it 'propagates failed_transient attempt status to the submission latest_status' do
      described_class.create!(
        submission:,
        status: 'failed_transient',
        failure_classification: 'transient',
        last_http_status: 500
      )

      expect(submission.reload.latest_status).to eq('failed_transient')
    end

    it 'propagates failed_permanent attempt status to the submission latest_status' do
      described_class.create!(
        submission:,
        status: 'failed_permanent',
        failure_classification: 'permanent',
        last_http_status: 422
      )

      expect(submission.reload.latest_status).to eq('failed_permanent')
    end

    it 'propagates succeeded attempt status to the submission latest_status' do
      described_class.create!(
        submission:,
        status: 'succeeded',
        last_http_status: 200
      )

      expect(submission.reload.latest_status).to eq('succeeded')
    end
  end
end
