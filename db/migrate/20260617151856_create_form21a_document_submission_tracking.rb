class CreateForm21aDocumentSubmissionTracking < ActiveRecord::Migration[7.2]
  def up
    create_enum :form21a_document_submission_status,
                %w[pending uploading succeeded failed_transient failed_permanent abandoned]

    create_enum :form21a_upload_failure_classification,
                %w[transient permanent]

    create_table :form21a_document_submissions do |t|
      t.timestamps null: false

      t.string :form_id, null: false, comment: 'form type of the submission'
      t.string :application_id, null: false, comment: 'GCLAWS application this document belongs to'
      t.uuid :form21a_attachment_guid, null: false, comment: 'guid of the Form21aAttachment / S3 object'
      t.integer :document_type, comment: 'GCLAWS document-type code'
      t.string :content_type, comment: 'content type needed to re-upload the document'

      t.jsonb :reference_data_ciphertext,
              comment: 'encrypted data that can be used to identify the resource - ie, original filename, ICN, user account ID, etc'
      t.text :encrypted_kms_key, comment: 'KMS key used to encrypt the reference data'
      t.boolean :needs_kms_rotation, default: false, null: false

      t.enum :latest_status,
             default: 'pending',
             enum_type: 'form21a_document_submission_status'

      t.datetime :next_retry_at, comment: 'timestamp when this document is eligible for re-drive'
      t.datetime :last_attempted_at, comment: 'timestamp of the last upload attempt'
      t.datetime :succeeded_at, comment: 'timestamp when this document upload succeeded'

      t.index :form21a_attachment_guid,
              unique: true,
              name: 'idx_form21a_doc_subs_on_attachment_guid'

      t.index :application_id,
              name: 'idx_form21a_doc_subs_on_application_id'

      t.index %i[latest_status next_retry_at],
              name: 'idx_form21a_doc_subs_on_status_and_retry_at'

      t.index :needs_kms_rotation,
              name: 'idx_form21a_doc_subs_on_needs_kms_rotation'
    end

    safety_assured do
      # Safe because both tables are created in this migration and cannot contain existing rows.
      create_table :form21a_document_submission_attempts do |t|
        t.timestamps null: false

        t.references :form21a_document_submission,
                     null: false,
                     foreign_key: {
                       to_table: :form21a_document_submissions,
                       name: 'fk_form21a_doc_attempts_on_submission_id'
                     },
                     index: {
                       name: 'idx_form21a_doc_attempts_on_submission_id'
                     }

        t.jsonb :metadata_ciphertext, comment: 'encrypted metadata sent with the submission'
        t.jsonb :error_message_ciphertext, comment: 'encrypted error message from the GCLAWS upload'
        t.jsonb :response_ciphertext, comment: 'encrypted response from the GCLAWS upload'

        t.text :encrypted_kms_key, comment: 'KMS key used to encrypt sensitive data'
        t.boolean :needs_kms_rotation, default: false, null: false

        t.enum :status,
               default: 'pending',
               enum_type: 'form21a_document_submission_status'

        t.integer :last_http_status, comment: 'HTTP status from GCLAWS on this attempt'

        t.enum :failure_classification,
               enum_type: 'form21a_upload_failure_classification'

        t.datetime :attempted_at, comment: 'timestamp when this upload attempt ran'

        t.index :needs_kms_rotation,
                name: 'idx_form21a_doc_attempts_on_needs_kms_rotation'
      end
    end
  end

  def down
    drop_table :form21a_document_submission_attempts
    drop_table :form21a_document_submissions

    drop_enum :form21a_upload_failure_classification
    drop_enum :form21a_document_submission_status
  end
end
