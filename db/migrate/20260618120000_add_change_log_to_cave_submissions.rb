class AddChangeLogToCaveSubmissions < ActiveRecord::Migration[7.2]
  def change
    # Encrypted, user-correction change log derived at claim submission (PII).
    add_column :cave_submissions, :change_log_ciphertext, :text
    # CAVE document id, kvpid, and the IDP user id captured at download, needed to forward
    # corrections back to CAVE (which authenticates per-user) after claim submission.
    add_column :cave_submissions, :cave_document_id, :string
    add_column :cave_submissions, :kvpid, :string
    add_column :cave_submissions, :idp_user_id, :string
    # Retention: set at creation so PII is purged on a fixed window (see CaveSubmissionPurgeJob).
    # The supporting index on delete_date is added CONCURRENTLY in a separate migration.
    add_column :cave_submissions, :delete_date, :datetime
  end
end
