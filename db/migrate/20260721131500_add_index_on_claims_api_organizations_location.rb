# frozen_string_literal: true

class AddIndexOnClaimsApiOrganizationsLocation < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_index :claims_api_organizations,
              :location,
              name: 'index_claims_api_organizations_on_location',
              using: :gist,
              algorithm: :concurrently
  end

  def down
    remove_index :claims_api_organizations,
                 name: 'index_claims_api_organizations_on_location',
                 if_exists: true,
                 algorithm: :concurrently
  end
end
