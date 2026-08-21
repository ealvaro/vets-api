# frozen_string_literal: true

class AddIndexToEvidenceSubmissionsOnUploadStatusAndDeleteDate < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_index :evidence_submissions, %i[upload_status delete_date],
              name: 'index_evidence_submissions_on_upload_status_and_delete_date',
              algorithm: :concurrently
  end

  def down
    remove_index :evidence_submissions, name: 'index_evidence_submissions_on_upload_status_and_delete_date',
                 algorithm: :concurrently, if_exists: true
  end
end
