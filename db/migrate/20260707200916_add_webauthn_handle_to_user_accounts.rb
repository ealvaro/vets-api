class AddWebauthnHandleToUserAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :user_accounts, :webauthn_handle, :string, null: true, if_not_exists: true
  end
end
