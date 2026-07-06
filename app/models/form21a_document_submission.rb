# frozen_string_literal: true

class Form21aDocumentSubmission < Submission
  include SubmissionEncryption

  self.table_name = 'form21a_document_submissions'

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
end
