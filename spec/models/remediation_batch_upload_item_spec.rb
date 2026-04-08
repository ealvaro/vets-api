# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RemediationBatchUploadItem, type: :model do
  subject { build(:remediation_batch_upload_item) }

  describe 'validations' do
    it { is_expected.to validate_presence_of(:submission_id) }
    it { is_expected.to validate_uniqueness_of(:submission_id) }
    it { is_expected.to validate_presence_of(:s3_bucket) }
    it { is_expected.to validate_presence_of(:s3_key) }
    it { is_expected.to validate_presence_of(:document_type_id) }
    it { is_expected.to validate_inclusion_of(:status).in_array(described_class::STATUSES) }

    describe 'error_message length' do
      it 'accepts messages up to 10,000 characters' do
        subject.error_message = 'a' * 10_000
        expect(subject).to be_valid
      end

      it 'rejects messages over 10,000 characters' do
        subject.error_message = 'a' * 10_001
        expect(subject).not_to be_valid
      end
    end

    describe 'claims_evidence_file_uuid format' do
      it 'accepts valid UUIDs' do
        subject.claims_evidence_file_uuid = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
        expect(subject).to be_valid
      end

      it 'rejects invalid UUID format' do
        subject.claims_evidence_file_uuid = 'not-a-uuid'
        expect(subject).not_to be_valid
      end

      it 'allows nil' do
        subject.claims_evidence_file_uuid = nil
        expect(subject).to be_valid
      end
    end
  end

  describe 'constants' do
    it 'defines STATUSES' do
      expect(described_class::STATUSES).to eq(%w[pending downloading uploading completed failed])
    end

    it 'defines MAX_RETRIES as 3' do
      expect(described_class::MAX_RETRIES).to eq(3)
    end
  end

  describe 'scopes' do
    describe '.actionable' do
      it 'returns pending items under retry limit' do
        pending_item = create(:remediation_batch_upload_item, status: 'pending', retry_count: 0)
        create(:remediation_batch_upload_item, :completed)
        create(:remediation_batch_upload_item, :exhausted)

        expect(described_class.actionable).to include(pending_item)
      end

      it 'returns failed items under retry limit' do
        failed_item = create(:remediation_batch_upload_item, :failed)
        expect(described_class.actionable).to include(failed_item)
      end

      it 'excludes failed items at or above retry limit' do
        exhausted = create(:remediation_batch_upload_item, :exhausted)
        expect(described_class.actionable).not_to include(exhausted)
      end

      it 'excludes completed items' do
        completed = create(:remediation_batch_upload_item, :completed)
        expect(described_class.actionable).not_to include(completed)
      end

      it 'excludes downloading/uploading items' do
        downloading = create(:remediation_batch_upload_item, :downloading)
        uploading = create(:remediation_batch_upload_item, :uploading)
        expect(described_class.actionable).not_to include(downloading, uploading)
      end

      it 'orders by id' do
        create(:remediation_batch_upload_item, status: 'pending')
        create(:remediation_batch_upload_item, status: 'pending')
        # IDs are sequential, so first created has lower id
        results = described_class.actionable
        expect(results.first.id).to be < results.last.id
      end
    end

    describe '.stale_in_progress' do
      it 'returns downloading items older than timeout' do
        stale = create(:remediation_batch_upload_item, :stale_downloading)
        expect(described_class.stale_in_progress).to include(stale)
      end

      it 'returns uploading items older than timeout' do
        stale = create(:remediation_batch_upload_item, :stale_uploading)
        expect(described_class.stale_in_progress).to include(stale)
      end

      it 'excludes recent in-progress items' do
        recent = create(:remediation_batch_upload_item, :downloading)
        expect(described_class.stale_in_progress).not_to include(recent)
      end

      it 'excludes pending/completed/failed items' do
        create(:remediation_batch_upload_item, status: 'pending')
        create(:remediation_batch_upload_item, :completed)
        create(:remediation_batch_upload_item, :failed)
        expect(described_class.stale_in_progress).to be_empty
      end

      it 'respects custom timeout' do
        item = create(:remediation_batch_upload_item, status: 'downloading', started_at: 3.minutes.ago)
        expect(described_class.stale_in_progress(timeout: 5.minutes.ago)).to be_empty
        expect(described_class.stale_in_progress(timeout: 2.minutes.ago)).to include(item)
      end
    end
  end
end
