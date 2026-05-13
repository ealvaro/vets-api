# frozen_string_literal: true

require 'sidekiq'

module AskVAApi
  class DeleteOldInquirySubmissionsJob
    include Sidekiq::Job

    sidekiq_options retry: false

    def perform
      total_inquiry_submissions = AskVAApi::InquirySubmission.count
      submissions = AskVAApi::InquirySubmission.where('ask_va_inquiry_submissions.created_at < ?', 60.days.ago)
      checkpoint_count = AskVAApi::InquirySubmissionCheckpoint.joins(:inquiry_submission).merge(submissions).count

      Rails.logger.info(
        'Delete Old Inquiry Submissions Job started',
        start_context(total_inquiry_submissions, submissions.count, checkpoint_count)
      )

      deletion_result = delete_submissions(submissions)

      Rails.logger.info(
        'Delete Old Inquiry Submissions Job completed',
        completion_context(deletion_result, total_inquiry_submissions)
      )
    rescue => e
      Rails.logger.error('Delete Old Inquiry Submissions Job unexpected error', unexpected_error_context(e))
      raise
    end

    private

    def start_context(total_inquiry_submissions, inquiry_submissions_to_delete, checkpoints_to_delete)
      {
        total_inquiry_submissions:,
        inquiry_submissions_to_delete:,
        checkpoints_to_delete:
      }
    end

    def delete_submissions(submissions)
      deleted_submissions = 0
      deleted_checkpoints = 0
      failed_submissions = 0
      failed_submission_ids = []

      submissions.find_each(batch_size: 1000) do |submission|
        submission_checkpoint_count = submission.inquiry_submission_checkpoints.size
        submission.destroy!
        deleted_submissions += 1
        deleted_checkpoints += submission_checkpoint_count
      rescue ActiveRecord::RecordNotDestroyed => e
        failed_submissions += 1
        failed_submission_ids << e.record.id
      end

      {
        deleted_submissions:,
        deleted_checkpoints:,
        failed_submissions:,
        failed_submission_ids:
      }
    end

    def completion_context(deletion_result, total_inquiry_submissions)
      {
        deleted_inquiry_submissions: deletion_result[:deleted_submissions],
        failed_inquiry_submissions: deletion_result[:failed_submissions],
        failed_inquiry_submission_ids: deletion_result[:failed_submission_ids],
        deleted_checkpoints: deletion_result[:deleted_checkpoints],
        percentage_of_total_inquiry_submissions_deleted: percentage_of_total_inquiry_submissions_deleted(
          deletion_result[:deleted_submissions],
          total_inquiry_submissions
        )
      }
    end

    def unexpected_error_context(error)
      {
        error: error.message
      }
    end

    def percentage_of_total_inquiry_submissions_deleted(deleted_submissions, total_inquiry_submissions)
      return 0 if total_inquiry_submissions.zero?

      ((deleted_submissions.to_f / total_inquiry_submissions) * 100).round
    end
  end
end
