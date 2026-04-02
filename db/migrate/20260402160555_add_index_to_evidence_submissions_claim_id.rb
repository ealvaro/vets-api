class AddIndexToEvidenceSubmissionsClaimId < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    add_index :evidence_submissions, :claim_id, algorithm: :concurrently
  end
end
