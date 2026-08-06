# frozen_string_literal: true

class AddIndexOnClaimsApiOrgRepsRepresentativeId < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_index :claims_api_organization_representatives,
              :representative_id,
              name: 'idx_claims_api_org_reps_on_representative_id',
              algorithm: :concurrently
  end

  def down
    remove_index :claims_api_organization_representatives,
                 name: 'idx_claims_api_org_reps_on_representative_id',
                 if_exists: true,
                 algorithm: :concurrently
  end
end
