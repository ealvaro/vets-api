# frozen_string_literal: true

class AddUniqueIndexOnClaimsApiOrganizationsPoa < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_index :claims_api_organizations,
              :poa,
              name: 'index_claims_api_organizations_on_poa',
              unique: true,
              algorithm: :concurrently
  end

  def down
    remove_index :claims_api_organizations,
                 name: 'index_claims_api_organizations_on_poa',
                 if_exists: true,
                 algorithm: :concurrently
  end
end
