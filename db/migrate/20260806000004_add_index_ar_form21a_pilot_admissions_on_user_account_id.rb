# frozen_string_literal: true

class AddIndexArForm21aPilotAdmissionsOnUserAccountId < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_index :ar_form21a_pilot_admissions, :user_account_id,
              unique: true,
              algorithm: :concurrently,
              if_not_exists: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
