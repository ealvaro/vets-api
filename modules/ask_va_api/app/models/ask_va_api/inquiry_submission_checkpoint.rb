# frozen_string_literal: true

class AskVAApi::InquirySubmissionCheckpoint < ApplicationRecord
  self.table_name = 'ask_va_inquiry_submission_checkpoints'

  VALID_CHECKPOINTS = %w[inbound_submission outbound_submission crm_response].freeze

  belongs_to :inquiry_submission,
             class_name: 'AskVAApi::InquirySubmission',
             foreign_key: 'ask_va_inquiry_submission_id',
             inverse_of: 'inquiry_submission_checkpoints'

  validates :ask_va_inquiry_submission_id, presence: true
  validates :checkpoint_type, presence: true, inclusion: { in: VALID_CHECKPOINTS }
  validates :payload, presence: true

  has_kms_key
  # per lockbox docs - Note: Use a text column for the ciphertext in migrations, regardless of the type
  # `payload` is exposed as json data while the encrypted db column data type should remain `text`
  has_encrypted :payload, type: :json, key: :kms_key, **lockbox_options
end
