# frozen_string_literal: true

class AddIndexToSavedClaimsOnFormId < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_index :saved_claims, :form_id, name: 'index_saved_claims_on_form_id', algorithm: :concurrently
  end

  def down
    remove_index :saved_claims, name: 'index_saved_claims_on_form_id', algorithm: :concurrently, if_exists: true
  end
end
