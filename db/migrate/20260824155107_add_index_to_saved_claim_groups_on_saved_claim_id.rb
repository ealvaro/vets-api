class AddIndexToSavedClaimGroupsOnSavedClaimId < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :saved_claim_groups, :saved_claim_id, algorithm: :concurrently, if_not_exists: true
  end
end
