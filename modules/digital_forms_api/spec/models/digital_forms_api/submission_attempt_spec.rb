# frozen_string_literal: true

require 'rails_helper'
require 'support/models/shared_examples/submission_attempt'

RSpec.describe DigitalFormsApi::SubmissionAttempt, type: :model do
  it_behaves_like 'a SubmissionAttempt model'

  it 'uses the digital_forms_api_submission_attempts table' do
    expect(described_class.table_name).to eq('digital_forms_api_submission_attempts')
  end

  describe 'factory' do
    it { expect(build(:digital_forms_api_submission_attempt)).to be_valid }
    it { expect(build(:digital_forms_api_submission_attempt, :accepted)).to be_valid }
    it { expect(build(:digital_forms_api_submission_attempt, :failed)).to be_valid }
  end

  describe 'status enum' do
    it 'defines pending/accepted/failed matching the shared PG enum' do
      expect(described_class.statuses).to eq(
        'pending' => 'pending', 'accepted' => 'accepted', 'failed' => 'failed'
      )
    end

    it 'defaults to pending' do
      expect(build(:digital_forms_api_submission_attempt).status).to eq('pending')
    end
  end

  describe 'associations' do
    it do
      expect(subject).to belong_to(:submission)
        .class_name('DigitalFormsApi::Submission')
        .with_foreign_key(:digital_forms_api_submission_id)
    end

    it { is_expected.to have_one(:saved_claim).through(:submission) }
  end

  describe 'encryption' do
    # Distinctive markers so the at-rest checks are meaningful (plaintext absence) without the
    # flakiness of matching short substrings against effectively-random ciphertext.
    let(:metadata_marker) { 'META-PLAINTEXT-MARKER-7b21' }
    let(:response_marker) { 'RESP-PLAINTEXT-MARKER-4c80' }
    let(:error_marker) { 'ERR-PLAINTEXT-MARKER-1d6e' }
    let(:attempt) do
      create(:digital_forms_api_submission_attempt,
             metadata: { 'formId' => metadata_marker },
             response: { 'submission' => { 'submissionId' => response_marker } },
             error_message: error_marker)
    end

    it 'round-trips metadata, response, and error_message' do
      attempt.reload
      expect(attempt.metadata).to eq('formId' => metadata_marker)
      expect(attempt.response).to eq('submission' => { 'submissionId' => response_marker })
      expect(attempt.error_message).to eq(error_marker)
    end

    it 'persists every encrypted field as ciphertext, not plaintext' do
      raw = attempt.reload.attributes_before_type_cast
      expect(raw['metadata_ciphertext']).to be_present
      expect(raw['response_ciphertext']).to be_present
      expect(raw['error_message_ciphertext']).to be_present
      expect(raw['metadata_ciphertext'].to_s).not_to include(metadata_marker)
      expect(raw['response_ciphertext'].to_s).not_to include(response_marker)
      expect(raw['error_message_ciphertext'].to_s).not_to include(error_marker)
    end

    it 'is registered as an encryption descendant (so the needs_kms_rotation guard covers it)' do
      expect(ApplicationRecord.descendants_using_encryption).to include(described_class)
      expect(described_class.column_names).to include('needs_kms_rotation')
    end
  end

  describe '.pending_for_polling' do
    it 'returns only pending attempts, oldest-touched first, excluding terminal ones' do
      old_pending = create(:digital_forms_api_submission_attempt, updated_at: 2.hours.ago)
      new_pending = create(:digital_forms_api_submission_attempt, updated_at: 5.minutes.ago)
      accepted = create(:digital_forms_api_submission_attempt, :accepted)
      failed = create(:digital_forms_api_submission_attempt, :failed)

      # Scope to this example's rows so the assertion is robust to any other data in the table.
      mine = [old_pending, new_pending, accepted, failed].map(&:id)
      result = described_class.pending_for_polling.where(id: mine)

      expect(result.map(&:status).uniq).to eq(['pending'])
      # Oldest updated_at first; explicit timestamps make the ordering deterministic.
      expect(result.map(&:id)).to eq([old_pending.id, new_pending.id])
    end
  end

  describe 'parent latest_status cascade (inherited base callback fires for this subclass)' do
    let(:submission) { create(:digital_forms_api_submission) }

    it 'updates the parent on create and on subsequent status change' do
      attempt = create(:digital_forms_api_submission_attempt, submission:)
      expect(submission.reload.latest_status).to eq('pending')

      attempt.update!(status: 'accepted')
      expect(submission.reload.latest_status).to eq('accepted')
    end
  end
end
