class AddLastStuckAlertedAtToForm21aDocumentSubmissions < ActiveRecord::Migration[8.1]
  def change
    add_column :form21a_document_submissions,
               :last_stuck_alerted_at,
               :datetime,
               comment: 'timestamp when Ops was last alerted that this document upload was stuck'
  end
end
