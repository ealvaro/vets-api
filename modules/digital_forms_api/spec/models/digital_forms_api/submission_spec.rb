# frozen_string_literal: true

require 'rails_helper'
require 'support/models/shared_examples/submission'

RSpec.describe DigitalFormsApi::Submission, type: :model do
  it_behaves_like 'a Submission model'

  it 'uses the digital_forms_api_submissions table' do
    expect(described_class.table_name).to eq('digital_forms_api_submissions')
  end

  describe 'factory' do
    it { expect(build(:digital_forms_api_submission)).to be_valid }
  end

  describe 'validations' do
    it 'requires form_id (inherited from ::Submission)' do
      record = build(:digital_forms_api_submission, form_id: nil)
      expect(record).not_to be_valid
      expect(record.errors[:form_id]).to be_present
    end

    it 'rejects a duplicate bip_submission_id' do
      create(:digital_forms_api_submission, bip_submission_id: 'dup-id')
      dupe = build(:digital_forms_api_submission, bip_submission_id: 'dup-id')
      expect(dupe).not_to be_valid
      expect(dupe.errors[:bip_submission_id]).to be_present
    end

    it 'allows multiple rows with a nil bip_submission_id (allow_nil + PG null-distinct index)' do
      create(:digital_forms_api_submission, bip_submission_id: nil)
      second = build(:digital_forms_api_submission, bip_submission_id: nil)
      expect(second).to be_valid
      expect { second.save! }.not_to raise_error
    end
  end

  describe 'associations' do
    it do
      expect(subject).to have_many(:submission_attempts)
        .class_name('DigitalFormsApi::SubmissionAttempt')
        .with_foreign_key(:digital_forms_api_submission_id)
        .dependent(:destroy)
    end

    it { is_expected.to belong_to(:user_account).optional }
    it { is_expected.to belong_to(:saved_claim).optional }
  end

  describe 'encryption' do
    # Distinctive marker so the at-rest check is meaningful (plaintext absence) without the
    # flakiness of matching a short substring against effectively-random ciphertext.
    let(:plaintext_marker) { 'EP-PLAINTEXT-MARKER-9f3a' }
    let(:submission) { create(:digital_forms_api_submission, reference_data: { 'ep_code' => plaintext_marker }) }

    it 'round-trips reference_data through the SubmissionEncryption concern' do
      expect(submission.reload.reference_data).to eq('ep_code' => plaintext_marker)
    end

    it 'persists reference_data encrypted at rest, not as plaintext' do
      raw = submission.reload.attributes_before_type_cast['reference_data_ciphertext']
      expect(raw).to be_present
      expect(raw.to_s).not_to include(plaintext_marker)
    end

    it 'is registered as an encryption descendant (so the needs_kms_rotation guard covers it)' do
      expect(ApplicationRecord.descendants_using_encryption).to include(described_class)
      expect(described_class.column_names).to include('needs_kms_rotation')
    end
  end

  describe 'latest_status cascade from the most recent attempt' do
    let(:submission) { create(:digital_forms_api_submission) }

    it 'defaults to pending' do
      expect(submission.latest_status).to eq('pending')
    end

    it 'reflects an attempt becoming accepted (after_create path)' do
      create(:digital_forms_api_submission_attempt, :accepted, submission:)
      expect(submission.reload.latest_status).to eq('accepted')
    end

    it 'reflects a later status change on the attempt (before_update path)' do
      attempt = create(:digital_forms_api_submission_attempt, submission:)
      expect { attempt.update!(status: 'failed') }
        .to change { submission.reload.latest_status }.from('pending').to('failed')
    end
  end

  describe 'dependent: :destroy' do
    it 'destroys child attempts when the submission is destroyed' do
      submission = create(:digital_forms_api_submission)
      create_list(:digital_forms_api_submission_attempt, 2, submission:)
      expect { submission.destroy }.to change(DigitalFormsApi::SubmissionAttempt, :count).by(-2)
    end
  end
end
