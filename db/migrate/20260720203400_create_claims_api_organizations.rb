# frozen_string_literal: true

class CreateClaimsApiOrganizations < ActiveRecord::Migration[8.1]
  def up
    create_table :claims_api_organizations, id: false do |t|
      t.string :address_line1
      t.string :address_line2
      t.string :address_line3
      t.string :address_type
      t.boolean :can_accept_digital_poa_requests, default: false
      t.string :city
      t.string :country_code_iso3
      t.string :country_name
      t.string :county_code
      t.string :county_name
      t.datetime :created_at, null: false
      t.string :default_new_rep_acceptance_mode, default: 'no_acceptance', null: false
      t.string :international_postal_code
      t.float :lat
      t.geography :location, limit: { srid: 4326, type: 'st_point', geographic: true }
      t.float :long
      t.string :name
      t.string :phone
      t.string :poa, limit: 3
      t.string :primary_org_acceptance_mode, default: 'no_acceptance', null: false
      t.string :province
      t.jsonb :raw_address
      t.string :state, limit: 2
      t.string :state_code
      t.datetime :updated_at, null: false
      t.string :zip_code
      t.string :zip_suffix
    end

    add_check_constraint :claims_api_organizations,
                         "default_new_rep_acceptance_mode::text = ANY (ARRAY['any_request'::character varying::text, 'self_only'::character varying::text, 'no_acceptance'::character varying::text])",
                         name: 'check_claims_api_orgs_default_new_rep_acceptance_mode'

    add_check_constraint :claims_api_organizations,
                         "primary_org_acceptance_mode::text = ANY (ARRAY['any_request'::character varying::text, 'self_only'::character varying::text, 'no_acceptance'::character varying::text])",
                         name: 'check_claims_api_orgs_primary_org_acceptance_mode'
  end

  def down
    drop_table :claims_api_organizations
  end
end
