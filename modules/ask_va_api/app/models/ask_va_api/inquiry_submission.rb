# frozen_string_literal: true

class AskVAApi::InquirySubmission < ApplicationRecord
  self.table_name = 'ask_va_inquiry_submissions'

  has_many :inquiry_submission_checkpoints,
           class_name: 'AskVAApi::InquirySubmissionCheckpoint',
           foreign_key: 'ask_va_inquiry_submission_id',
           dependent: :destroy,
           inverse_of: 'inquiry_submission'

  validates :request_id, presence: true
end
