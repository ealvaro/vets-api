# frozen_string_literal: true

class CreateDigitalFormsApiSubmissionAttempts < ActiveRecord::Migration[7.2]
  def change
    create_table :digital_forms_api_submission_attempts do |t|
      t.references :digital_forms_api_submission, null: false, foreign_key: true,
                                                  comment: 'parent submission'
      t.enum :status, enum_type: 'digital_forms_api_submission_status', default: 'pending',
                      comment: 'attempt status; cascaded into the parent latest_status by the base callback'
      t.jsonb :metadata_ciphertext, comment: 'encrypted metadata sent with the submission'
      t.jsonb :response_ciphertext, comment: 'encrypted response from the digital forms api submission'
      t.jsonb :error_message_ciphertext, comment: 'encrypted error message from the digital forms api submission'
      t.text :encrypted_kms_key, comment: 'KMS key used to encrypt sensitive data'
      t.boolean :needs_kms_rotation, default: false, null: false,
                                     comment: 'flag for daily KmsKeyRotation::BatchInitiatorJob re-encryption'

      t.timestamps

      t.index :status, name: 'index_dfa_submission_attempts_on_status'
      t.index :needs_kms_rotation, name: 'index_dfa_submission_attempts_on_needs_kms_rotation'
    end
  end
end
