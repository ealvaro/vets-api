class AddCaseflowClaimIdToEvidenceSubmissions < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    add_column :evidence_submissions, :caseflow_claim_id, :string
    add_index :evidence_submissions, :caseflow_claim_id, algorithm: :concurrently
  end
end
