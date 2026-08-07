# frozen_string_literal: true

class DropInvalidIndexArForm21aPilotAdmissionsUserAccountId < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    remove_index :ar_form21a_pilot_admissions,
                 name: 'index_ar_form21a_pilot_admissions_on_user_account_id',
                 algorithm: :concurrently,
                 if_exists: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
