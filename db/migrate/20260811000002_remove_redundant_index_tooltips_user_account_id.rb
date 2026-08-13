# frozen_string_literal: true

class RemoveRedundantIndexTooltipsUserAccountId < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    # All queries against tooltips use the composite unique index
    # (user_account_id, tooltip_name) or a PK lookup; this single-column
    # index adds no selectivity benefit not already covered by the composite prefix.
    remove_index :tooltips,
                 name: 'index_tooltips_on_user_account_id',
                 algorithm: :concurrently,
                 if_exists: true
  end

  def down
    add_index :tooltips,
              :user_account_id,
              name: 'index_tooltips_on_user_account_id',
              algorithm: :concurrently
  end
end
