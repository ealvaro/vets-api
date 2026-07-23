# frozen_string_literal: true

class Form21aDocumentSubmission < Submission
  include SubmissionEncryption

  self.table_name = 'form21a_document_submissions'

  REDRIVE_MAX_ATTEMPTS = 12
  STUCK_THRESHOLD = 6.hours
  ABANDON_THRESHOLD = 7.days

  has_many :submission_attempts,
           class_name: 'Form21aDocumentSubmissionAttempt',
           inverse_of: :submission,
           dependent: :destroy

  enum :latest_status, {
    pending: 'pending',
    uploading: 'uploading',
    succeeded: 'succeeded',
    failed_transient: 'failed_transient',
    failed_permanent: 'failed_permanent',
    abandoned: 'abandoned'
  }, prefix: true

  scope :redrivable, lambda {
    latest_status_failed_transient
      .where('next_retry_at <= ?', Time.current)
  }

  scope :stuck, lambda {
    where(latest_status: %w[pending uploading])
      .where('created_at <= ?', STUCK_THRESHOLD.ago)
  }

  def original_file_name
    reference_data&.dig('original_file_name')
  end

  def original_file_name=(value)
    self.reference_data = (reference_data || {}).merge('original_file_name' => value)
  end

  def identifiers
    reference_data&.dig('identifiers') || {}
  end

  def identifiers=(value)
    self.reference_data = (reference_data || {}).merge('identifiers' => value)
  end

  def attempt_count
    submission_attempts.count
  end

  def genuinely_stuck?
    max_attempts_reached? || older_than_abandon_threshold?
  end

  def retry_due?
    latest_status_failed_transient? &&
      next_retry_at.present? &&
      next_retry_at <= Time.current
  end

  private

  def max_attempts_reached?
    attempt_count >= REDRIVE_MAX_ATTEMPTS
  end

  def older_than_abandon_threshold?
    created_at.present? && created_at <= ABANDON_THRESHOLD.ago
  end
end
