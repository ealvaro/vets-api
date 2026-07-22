# frozen_string_literal: true

class CreateArRepresentativeInProgressForms < ActiveRecord::Migration[7.2]
  def change
    create_table :ar_representative_in_progress_forms, id: :uuid do |t|
      t.references :rep_user_account,
                   type: :uuid,
                   foreign_key: { to_table: :user_accounts },
                   null: false,
                   index: false

      t.string :veteran_icn, null: false
      t.string :form_id, null: false

      t.text :encrypted_kms_key
      t.text :form_data_ciphertext
      t.boolean :needs_kms_rotation, default: false, null: false

      t.json :metadata
      t.datetime :expires_at

      t.timestamps
    end
  end
end
