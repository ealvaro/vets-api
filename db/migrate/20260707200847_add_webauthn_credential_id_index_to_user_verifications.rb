class AddWebauthnCredentialIdIndexToUserVerifications < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :user_verifications, :webauthn_credential_id, unique: true, algorithm: :concurrently,
                                                            where: 'webauthn_credential_id IS NOT NULL',
                                                            if_not_exists: true
  end
end
