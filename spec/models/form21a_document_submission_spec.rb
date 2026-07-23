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

  def create_submission(attributes = {})
    described_class.create!(
      valid_attributes.merge(
        form21a_attachment_guid: SecureRandom.uuid
      ).merge(attributes)
    )
  end

  def create_attempts(submission, count:, status: 'failed_transient')
    count.times do
      Form21aDocumentSubmissionAttempt.create!(
        submission:,
        status:,
        failure_classification: status == 'failed_transient' ? 'transient' : nil
      )
    end
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

  describe '.redrivable' do
    it 'returns only failed_transient submissions whose next_retry_at is due' do
      due_transient = create_submission(
        latest_status: 'failed_transient',
        next_retry_at: 1.minute.ago
      )

      create_submission(
        latest_status: 'failed_transient',
        next_retry_at: 1.minute.from_now
      )
      create_submission(
        latest_status: 'failed_transient',
        next_retry_at: nil
      )
      create_submission(
        latest_status: 'failed_permanent',
        next_retry_at: 1.minute.ago
      )
      create_submission(
        latest_status: 'succeeded',
        next_retry_at: 1.minute.ago
      )
      create_submission(
        latest_status: 'abandoned',
        next_retry_at: 1.minute.ago
      )
      create_submission(
        latest_status: 'pending',
        next_retry_at: 1.minute.ago
      )
      create_submission(
        latest_status: 'uploading',
        next_retry_at: 1.minute.ago
      )

      expect(described_class.redrivable).to contain_exactly(due_transient)
    end
  end

  describe '.stuck' do
    it 'returns pending and uploading submissions older than the stuck threshold' do
      old_pending = create_submission(latest_status: 'pending')
      old_uploading = create_submission(latest_status: 'uploading')

      # rubocop:disable Rails/SkipsModelValidations
      old_pending.update_columns(created_at: described_class::STUCK_THRESHOLD.ago - 1.minute)
      old_uploading.update_columns(created_at: described_class::STUCK_THRESHOLD.ago - 1.minute)
      # rubocop:enable Rails/SkipsModelValidations
      recent_pending = create_submission(latest_status: 'pending')
      recent_uploading = create_submission(latest_status: 'uploading')
      old_failed_transient = create_submission(latest_status: 'failed_transient')
      old_succeeded = create_submission(latest_status: 'succeeded')
      old_abandoned = create_submission(latest_status: 'abandoned')
      # rubocop:disable Rails/SkipsModelValidations
      old_failed_transient.update_columns(created_at: described_class::STUCK_THRESHOLD.ago - 1.minute)
      old_succeeded.update_columns(created_at: described_class::STUCK_THRESHOLD.ago - 1.minute)
      old_abandoned.update_columns(created_at: described_class::STUCK_THRESHOLD.ago - 1.minute)
      # rubocop:enable Rails/SkipsModelValidations
      expect(described_class.stuck).to contain_exactly(old_pending, old_uploading)
      expect(described_class.stuck).not_to include(
        recent_pending,
        recent_uploading,
        old_failed_transient,
        old_succeeded,
        old_abandoned
      )
    end
  end

  describe '#attempt_count' do
    it 'returns the number of submission attempts' do
      submission = described_class.create!(valid_attributes)

      create_attempts(submission, count: 3)

      expect(submission.attempt_count).to eq(3)
    end
  end

  describe '#genuinely_stuck?' do
    it 'returns true when the max redrive attempts have been reached' do
      submission = described_class.create!(valid_attributes)

      create_attempts(
        submission,
        count: described_class::REDRIVE_MAX_ATTEMPTS
      )

      expect(submission.reload).to be_genuinely_stuck
    end

    it 'returns true when the submission is older than the abandon threshold' do
      submission = described_class.create!(valid_attributes)
      # rubocop:disable Rails/SkipsModelValidations
      submission.update_columns(created_at: described_class::ABANDON_THRESHOLD.ago - 1.minute)
      # rubocop:enable Rails/SkipsModelValidations
      expect(submission.reload).to be_genuinely_stuck
    end

    it 'returns false when under the attempt and age thresholds' do
      submission = described_class.create!(valid_attributes)

      create_attempts(
        submission,
        count: described_class::REDRIVE_MAX_ATTEMPTS - 1
      )

      expect(submission.reload).not_to be_genuinely_stuck
    end
  end

  describe '#retry_due?' do
    it 'returns true for failed_transient submissions whose next_retry_at is due' do
      submission = described_class.create!(
        valid_attributes.merge(
          latest_status: 'failed_transient',
          next_retry_at: 1.minute.ago
        )
      )

      expect(submission).to be_retry_due
    end

    it 'returns false when next_retry_at is in the future' do
      submission = described_class.create!(
        valid_attributes.merge(
          latest_status: 'failed_transient',
          next_retry_at: 1.minute.from_now
        )
      )

      expect(submission).not_to be_retry_due
    end

    it 'returns false when next_retry_at is nil' do
      submission = described_class.create!(
        valid_attributes.merge(
          latest_status: 'failed_transient',
          next_retry_at: nil
        )
      )

      expect(submission).not_to be_retry_due
    end

    it 'returns false when the status is not failed_transient' do
      submission = described_class.create!(
        valid_attributes.merge(
          latest_status: 'failed_permanent',
          next_retry_at: 1.minute.ago
        )
      )

      expect(submission).not_to be_retry_due
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
