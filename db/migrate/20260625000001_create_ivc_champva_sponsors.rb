# frozen_string_literal: true

class CreateIvcChampvaSponsors < ActiveRecord::Migration[7.2]
  def change
    create_table :ivc_champva_sponsors do |t|
      # Links to ivc_champva_forms via transaction_uuid (1-to-1 per application).
      #
      # Intentionally not an FK: ivc_champva_forms does not have a unique key on
      # transaction_uuid because a single application may persist multiple form
      # rows/documents under the same transaction UUID.
      t.uuid :transaction_uuid, null: false

      # Sponsor identity — from VES ICN lookup (encrypted)
      t.text :sponsor_icn_ciphertext
      t.text :first_name_ciphertext
      t.text :last_name_ciphertext
      t.string :eligibility_status
      t.string :reason

      # KMS envelope key used by lockbox encryption
      t.text :encrypted_kms_key

      t.timestamps
    end
  end
end
