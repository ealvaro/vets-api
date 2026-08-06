# frozen_string_literal: true

class CreateClaimsApiRepresentatives < ActiveRecord::Migration[8.1]
  def up
    create_table :claims_api_representatives, id: false do |t|
      t.string :address_line1
      t.string :address_line2
      t.string :address_line3
      t.string :address_type
      t.string :city
      t.string :country_code_iso3
      t.string :country_name
      t.string :county_code
      t.string :county_name
      t.datetime :created_at, null: false
      t.string :email
      t.datetime :fallback_location_updated_at
      t.string :first_name
      t.string :full_name
      t.string :international_postal_code
      t.string :last_name
      t.float :lat
      t.geography :location, limit: { srid: 4326, type: 'st_point', geographic: true }
      t.float :long
      t.string :middle_initial
      t.string :phone
      t.string :phone_number
      t.string :poa_codes, default: [], array: true
      t.string :province
      t.jsonb :raw_address
      t.string :representative_id
      t.string :state_code
      t.datetime :updated_at, null: false
      t.string :user_types, default: [], array: true
      t.string :zip_code
      t.string :zip_suffix
    end

    add_check_constraint :claims_api_representatives,
                         'representative_id IS NOT NULL',
                         name: 'claims_api_representatives_representative_id_null'
  end

  def down
    drop_table :claims_api_representatives
  end
end
