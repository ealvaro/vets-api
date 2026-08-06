# frozen_string_literal: true

class AddIndexOnClaimsApiRepresentativesLowerEmail < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_index :claims_api_representatives,
              'lower((email)::text)',
              name: 'index_claims_api_representatives_on_lower_email',
              algorithm: :concurrently
  end

  def down
    remove_index :claims_api_representatives,
                 name: 'index_claims_api_representatives_on_lower_email',
                 if_exists: true,
                 algorithm: :concurrently
  end
end
