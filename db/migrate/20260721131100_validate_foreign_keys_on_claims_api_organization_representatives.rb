# frozen_string_literal: true

class ValidateForeignKeysOnClaimsApiOrganizationRepresentatives < ActiveRecord::Migration[8.1]
  def up
    validate_foreign_key :claims_api_organization_representatives,
                         :claims_api_representatives,
                         column: :representative_id,
                         primary_key: :representative_id

    validate_foreign_key :claims_api_organization_representatives,
                         :claims_api_organizations,
                         column: :organization_poa,
                         primary_key: :poa
  end

  def down
    # no-op: validation state is not reversible
  end
end
