# frozen_string_literal: true

class AddUniqueIndexOnClaimsApiOrgRepsComposite < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_index :claims_api_organization_representatives,
              %i[organization_poa representative_id],
              name: 'idx_claims_api_org_reps_on_org_poa_and_rep_id',
              unique: true,
              algorithm: :concurrently
  end

  def down
    remove_index :claims_api_organization_representatives,
                 name: 'idx_claims_api_org_reps_on_org_poa_and_rep_id',
                 if_exists: true,
                 algorithm: :concurrently
  end
end
