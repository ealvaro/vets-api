# frozen_string_literal: true

class CreateSignInSessionRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :sign_in_session_records do |t|
      t.uuid :handle, null: false, index: { unique: true }
      t.references :user_account, type: :uuid, foreign_key: true, null: false, index: true
      t.string :client_id, null: false
      t.text :encrypted_kms_key
      t.boolean :needs_kms_rotation, default: false, null: false
      t.text :sign_in_ip_ciphertext
      t.text :user_agent_ciphertext
      t.datetime :last_activity_at
      t.datetime :signed_out_at, null: true
      t.string :device_description, null: true
      t.text :location_ciphertext, null: true
      t.timestamps
    end
  end
end
