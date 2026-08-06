# frozen_string_literal: true

class AddUniqueIndexOnClaimsApiRepresentativesRepresentativeId < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_index :claims_api_representatives,
              :representative_id,
              name: 'index_claims_api_representatives_on_representative_id',
              unique: true,
              algorithm: :concurrently
  end

  def down
    remove_index :claims_api_representatives,
                 name: 'index_claims_api_representatives_on_representative_id',
                 if_exists: true,
                 algorithm: :concurrently
  end
end
