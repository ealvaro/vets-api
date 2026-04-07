# frozen_string_literal: true

class CreateRemediationBatchUploadItems < ActiveRecord::Migration[7.2]
  def up # rubocop:disable Metrics/MethodLength
    create_table :remediation_batch_upload_items do |t|
      # Manifest data (from CSV)
      t.string :submission_id, null: false
      t.string :s3_bucket, null: false
      t.text :s3_key, null: false
      t.integer :document_type_id, null: false
      t.datetime :submission_datetime
      t.string :form_type
      t.string :subject

      # Progress tracking
      t.string :status, null: false, default: 'pending'
      t.string :error_class
      t.text :error_message
      t.integer :retry_count, null: false, default: 0
      t.datetime :started_at
      t.datetime :completed_at

      # API response
      t.string :claims_evidence_file_uuid

      t.timestamps
    end

    add_index :remediation_batch_upload_items, :submission_id, unique: true
    add_index :remediation_batch_upload_items, %i[status retry_count]
    add_index :remediation_batch_upload_items, %i[status started_at]
    add_index :remediation_batch_upload_items, :claims_evidence_file_uuid,
              unique: true,
              where: 'claims_evidence_file_uuid IS NOT NULL',
              name: 'idx_unique_claims_evidence_file_uuid'

    # CHECK constraints on a brand-new (0-row) table — safe per Strong Migrations guidance
    safety_assured do
      execute <<-SQL.squish
        ALTER TABLE remediation_batch_upload_items
          ADD CONSTRAINT chk_status
          CHECK (status IN ('pending', 'downloading', 'uploading', 'completed', 'failed'))
      SQL

      execute <<-SQL.squish
        ALTER TABLE remediation_batch_upload_items
          ADD CONSTRAINT chk_retry_count
          CHECK (retry_count >= 0 AND retry_count <= 3)
      SQL
    end
  end

  def down
    drop_table :remediation_batch_upload_items
  end
end
