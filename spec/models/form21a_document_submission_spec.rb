# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Form21aDocumentSubmission, type: :model do
  let(:form21a_attachment_guid) { SecureRandom.uuid }

  let(:valid_attributes) do
    {
      form_id: '21a',
      application_id: 12_345,
      form21a_attachment_guid:,
      document_type: '1',
      content_type: 'application/pdf'
    }
  end

  describe 'associations' do
    it 'has many submission attempts' do
      association = described_class.reflect_on_association(:submission_attempts)

      expect(association.macro).to eq(:has_many)
      expect(association.class_name).to eq('Form21aDocumentSubmissionAttempt')
      expect(association.options[:inverse_of]).to eq(:submission)
      expect(association.options[:dependent]).to eq(:destroy)
    end
  end

  describe 'enums' do
    it 'defines the expected latest_status values' do
      expect(described_class.latest_statuses).to eq(
        'pending' => 'pending',
        'uploading' => 'uploading',
        'succeeded' => 'succeeded',
        'failed_transient' => 'failed_transient',
        'failed_permanent' => 'failed_permanent',
        'abandoned' => 'abandoned'
      )
    end
  end

  describe 'defaults' do
    it 'defaults latest_status to pending' do
      submission = described_class.create!(valid_attributes)

      expect(submission.latest_status).to eq('pending')
      expect(submission).to be_latest_status_pending
    end
  end

  describe 'encrypted reference_data accessors' do
    it 'stores and retrieves original_file_name through encrypted reference_data' do
      submission = described_class.create!(valid_attributes)

      submission.original_file_name = 'test_document.pdf'
      submission.save!

      submission.reload

      expect(submission.original_file_name).to eq('test_document.pdf')
      expect(submission.reference_data).to include(
        'original_file_name' => 'test_document.pdf'
      )
      expect(submission.reference_data_ciphertext).to be_present
      expect(submission.reference_data_ciphertext.to_s).not_to include('test_document.pdf')
    end

    it 'stores and retrieves identifiers through encrypted reference_data' do
      identifiers = {
        'form21a_attachment_guid' => form21a_attachment_guid,
        'application_id' => '12345',
        'document_type' => '1'
      }

      submission = described_class.create!(valid_attributes)

      submission.identifiers = identifiers
      submission.save!

      submission.reload

      expect(submission.identifiers).to eq(identifiers)
      expect(submission.reference_data).to include(
        'identifiers' => identifiers
      )
      expect(submission.reference_data_ciphertext).to be_present
      expect(submission.reference_data_ciphertext.to_s).not_to include(form21a_attachment_guid)
    end

    it 'returns an empty hash for identifiers when none are present' do
      submission = described_class.new(valid_attributes)

      expect(submission.identifiers).to eq({})
    end

    it 'preserves existing reference_data values when setting original_file_name' do
      submission = described_class.create!(valid_attributes)

      submission.identifiers = {
        'form21a_attachment_guid' => form21a_attachment_guid
      }
      submission.original_file_name = 'test_document.pdf'
      submission.save!

      submission.reload

      expect(submission.identifiers).to eq(
        'form21a_attachment_guid' => form21a_attachment_guid
      )
      expect(submission.original_file_name).to eq('test_document.pdf')
    end

    it 'preserves existing reference_data values when setting identifiers' do
      submission = described_class.create!(valid_attributes)

      submission.original_file_name = 'test_document.pdf'
      submission.identifiers = {
        'application_id' => '12345'
      }
      submission.save!

      submission.reload

      expect(submission.original_file_name).to eq('test_document.pdf')
      expect(submission.identifiers).to eq(
        'application_id' => '12345'
      )
    end
  end

  describe 'content_type' do
    it 'stores and retrieves the content type from the database column' do
      submission = described_class.create!(valid_attributes)

      expect(submission.reload.content_type).to eq('application/pdf')
      expect(submission[:content_type]).to eq('application/pdf')
    end
  end
end
