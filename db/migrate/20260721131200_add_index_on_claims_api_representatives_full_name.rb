# frozen_string_literal: true

class AddIndexOnClaimsApiRepresentativesFullName < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_index :claims_api_representatives,
              :full_name,
              name: 'index_claims_api_representatives_on_full_name',
              algorithm: :concurrently
  end

  def down
    remove_index :claims_api_representatives,
                 name: 'index_claims_api_representatives_on_full_name',
                 if_exists: true,
                 algorithm: :concurrently
  end
end
