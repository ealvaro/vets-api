class AddIndexToForm21aDocumentSubmissionsLastStuckAlertedAt < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :form21a_document_submissions,
              :last_stuck_alerted_at,
              name: 'idx_form21a_doc_subs_on_last_stuck_alerted_at',
              algorithm: :concurrently
  end
end
