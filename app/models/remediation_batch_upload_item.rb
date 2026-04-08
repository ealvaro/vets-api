# frozen_string_literal: true

class RemediationBatchUploadItem < ApplicationRecord
  STATUSES = %w[pending downloading uploading completed failed].freeze
  MAX_RETRIES = 3
  STALE_TIMEOUT = 10.minutes.freeze

  validates :submission_id, presence: true, uniqueness: true
  validates :s3_bucket, :s3_key, :document_type_id, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :retry_count, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: MAX_RETRIES }
  validates :error_message, length: { maximum: 10_000 }, allow_nil: true
  validates :claims_evidence_file_uuid, format: { with: /\A[0-9a-f-]{36}\z/i }, allow_nil: true

  scope :actionable, lambda {
    where(status: %w[pending failed])
      .where('retry_count < ?', MAX_RETRIES)
      .order(:id)
  }

  scope :stale_in_progress, lambda { |timeout: STALE_TIMEOUT.ago|
    where(status: %w[downloading uploading])
      .where('started_at < ?', timeout)
  }
end
