# frozen_string_literal: true

class Form21aDocumentSubmissionAttempt < SubmissionAttempt
  include SubmissionAttemptEncryption

  self.table_name = 'form21a_document_submission_attempts'

  belongs_to :submission,
             class_name: 'Form21aDocumentSubmission',
             foreign_key: :form21a_document_submission_id,
             inverse_of: :submission_attempts

  enum :status, {
    pending: 'pending',
    uploading: 'uploading',
    succeeded: 'succeeded',
    failed_transient: 'failed_transient',
    failed_permanent: 'failed_permanent',
    abandoned: 'abandoned'
  }, prefix: true

  enum :failure_classification, {
    transient: 'transient',
    permanent: 'permanent'
  }, prefix: true
end
