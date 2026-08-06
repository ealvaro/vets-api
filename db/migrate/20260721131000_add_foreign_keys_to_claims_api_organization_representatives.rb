# frozen_string_literal: true

class AddForeignKeysToClaimsApiOrganizationRepresentatives < ActiveRecord::Migration[8.1]
  def up
    add_foreign_key :claims_api_organization_representatives,
                    :claims_api_representatives,
                    column: :representative_id,
                    primary_key: :representative_id,
                    validate: false

    add_foreign_key :claims_api_organization_representatives,
                    :claims_api_organizations,
                    column: :organization_poa,
                    primary_key: :poa,
                    validate: false
  end

  def down
    remove_foreign_key :claims_api_organization_representatives,
                       column: :organization_poa,
                       primary_key: :poa

    remove_foreign_key :claims_api_organization_representatives,
                       column: :representative_id,
                       primary_key: :representative_id
  end
end
