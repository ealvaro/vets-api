# frozen_string_literal: true

class CreateClaimsApiOrganizationRepresentatives < ActiveRecord::Migration[8.1]
  def up
    create_table :claims_api_organization_representatives do |t|
      t.string :representative_id, null: false
      t.string :organization_poa, limit: 3, null: false
      t.string :acceptance_mode, default: 'no_acceptance', null: false
      t.datetime :deactivated_at
      t.timestamps

      t.check_constraint "acceptance_mode::text = ANY (ARRAY['any_request'::character varying::text, 'self_only'::character varying::text, 'no_acceptance'::character varying::text])",
                         name: 'claims_api_org_reps_acceptance_mode_check'
    end
  end

  def down
    drop_table :claims_api_organization_representatives
  end
end
