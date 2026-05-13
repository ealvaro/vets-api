# frozen_string_literal: true

require 'rails_helper'
require 'fugit'

RSpec.describe AskVAApi::DeleteOldInquirySubmissionsJob, type: :job do
  include ActiveSupport::Testing::TimeHelpers

  describe 'schedule' do
    sidekiq_file = Rails.root.join('lib', 'periodic_jobs.rb')
    lines = File.readlines(sidekiq_file).grep(/AskVAApi::DeleteOldInquirySubmissionsJob/i)
    schedule =
      lines.first
           .gsub("  mgr.register('", '')
           .gsub("', 'AskVAApi::DeleteOldInquirySubmissionsJob')\n", '')

    let(:parsed_schedule) { Fugit.do_parse(schedule) }

    it 'is scheduled to run daily at 4:30 AM Eastern' do
      expect(parsed_schedule.original).to eq('30 4 * * *')
      expect(parsed_schedule.hours).to eq([4])
      expect(parsed_schedule.minutes).to eq([30])
    end
  end

  describe '#perform' do
    around do |example|
      travel_to(Time.zone.parse('2026-04-23 12:00:00')) { example.run }
    end

    let!(:old_submission) { create(:ask_va_api_inquiry_submission, created_at: 61.days.ago, updated_at: 61.days.ago) }
    let!(:old_checkpoint) do
      create(
        :ask_va_api_inquiry_submission_checkpoint,
        inquiry_submission: old_submission,
        created_at: 61.days.ago,
        updated_at: 61.days.ago
      )
    end
    let!(:recent_submission) do
      create(:ask_va_api_inquiry_submission, created_at: 59.days.ago, updated_at: 59.days.ago)
    end
    let!(:recent_checkpoint) do
      create(
        :ask_va_api_inquiry_submission_checkpoint,
        inquiry_submission: recent_submission,
        created_at: 59.days.ago,
        updated_at: 59.days.ago
      )
    end

    it 'logs deletion counts for observability' do
      expect(Rails.logger).to receive(:info).with(
        'Delete Old Inquiry Submissions Job started',
        {
          total_inquiry_submissions: 2,
          inquiry_submissions_to_delete: 1,
          checkpoints_to_delete: 1
        }
      )

      expect(Rails.logger).to receive(:info).with(
        'Delete Old Inquiry Submissions Job completed',
        {
          deleted_inquiry_submissions: 1,
          failed_inquiry_submissions: 0,
          failed_inquiry_submission_ids: [],
          deleted_checkpoints: 1,
          percentage_of_total_inquiry_submissions_deleted: 50
        }
      )

      described_class.new.perform
    end

    it 'purges inquiry submissions older than 60 days and their associated checkpoints' do
      expect do
        described_class.new.perform
      end.to change(AskVAApi::InquirySubmission, :count)
        .by(-1).and change(AskVAApi::InquirySubmissionCheckpoint, :count).by(-1)

      expect(AskVAApi::InquirySubmission.exists?(old_submission.id)).to be(false)
      expect(AskVAApi::InquirySubmissionCheckpoint.exists?(old_checkpoint.id)).to be(false)
      expect(AskVAApi::InquirySubmission.exists?(recent_submission.id)).to be(true)
      expect(AskVAApi::InquirySubmissionCheckpoint.exists?(recent_checkpoint.id)).to be(true)
    end

    it 'does not purge records created exactly 60 days ago' do
      boundary_submission = create(
        :ask_va_api_inquiry_submission,
        created_at: 60.days.ago,
        updated_at: 60.days.ago
      )
      boundary_checkpoint = create(
        :ask_va_api_inquiry_submission_checkpoint,
        inquiry_submission: boundary_submission,
        created_at: 60.days.ago,
        updated_at: 60.days.ago
      )

      expect { described_class.new.perform }
        .not_to change { AskVAApi::InquirySubmission.exists?(boundary_submission.id) }.from(true)

      expect(AskVAApi::InquirySubmissionCheckpoint.exists?(boundary_checkpoint.id)).to be(true)
    end

    it 'summarizes record deletion failures and continues processing remaining submissions' do
      second_old_submission = create(
        :ask_va_api_inquiry_submission,
        created_at: 61.days.ago,
        updated_at: 61.days.ago
      )
      create(
        :ask_va_api_inquiry_submission_checkpoint,
        inquiry_submission: second_old_submission,
        created_at: 61.days.ago,
        updated_at: 61.days.ago
      )

      allow_any_instance_of(AskVAApi::InquirySubmission).to receive(:destroy!) do |record|
        raise ActiveRecord::RecordNotDestroyed.new('failed to destroy record', record) if record.id == old_submission.id

        record.destroy
      end

      allow(Rails.logger).to receive(:info)
      expect(Rails.logger).to receive(:info).with(
        'Delete Old Inquiry Submissions Job completed',
        hash_including(
          deleted_inquiry_submissions: 1,
          failed_inquiry_submissions: 1,
          failed_inquiry_submission_ids: [old_submission.id]
        )
      )

      described_class.new.perform

      expect(AskVAApi::InquirySubmission.exists?(old_submission.id)).to be(true)
      expect(AskVAApi::InquirySubmission.exists?(second_old_submission.id)).to be(false)
    end

    it 'logs and re-raises unexpected errors' do
      allow(AskVAApi::InquirySubmission).to receive(:count).and_raise(StandardError, 'unexpected failure')

      expect(Rails.logger).to receive(:error).with(
        'Delete Old Inquiry Submissions Job unexpected error',
        { error: 'unexpected failure' }
      )

      expect { described_class.new.perform }.to raise_error(StandardError, 'unexpected failure')
    end
  end
end
