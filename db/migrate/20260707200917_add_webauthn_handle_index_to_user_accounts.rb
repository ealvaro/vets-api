class AddWebauthnHandleIndexToUserAccounts < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :user_accounts, :webauthn_handle, unique: true,
                                                where: 'webauthn_handle IS NOT NULL',
                                                algorithm: :concurrently,
                                                if_not_exists: true
  end
end
