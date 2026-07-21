# frozen_string_literal: true

class AddIndexesToArForm21aPilotAdmissions < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    # Enforces one admission per user, ever.
    add_index :ar_form21a_pilot_admissions, :user_account_id,
              unique: true,
              algorithm: :concurrently,
              if_not_exists: true,
              name: 'index_ar_form21a_pilot_admissions_on_user_account_id'

    # Backs the monthly (Eastern-month bucket) count query used by the pilot cap.
    add_index :ar_form21a_pilot_admissions, :created_at,
              algorithm: :concurrently,
              if_not_exists: true,
              name: 'index_ar_form21a_pilot_admissions_on_created_at'
  end
end
