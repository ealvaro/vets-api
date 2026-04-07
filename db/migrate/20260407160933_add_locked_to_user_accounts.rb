# frozen_string_literal: true

class AddLockedToUserAccounts < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!
  def change
    add_column :user_accounts, :locked, :boolean, default: false, null: false
    add_index :user_accounts, :locked, where: 'locked = true', algorithm: :concurrently
  end
end
