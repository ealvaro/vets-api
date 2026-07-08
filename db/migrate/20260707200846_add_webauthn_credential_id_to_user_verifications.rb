class AddWebauthnCredentialIdToUserVerifications < ActiveRecord::Migration[8.1]
  def change
    add_column :user_verifications, :webauthn_credential_id, :uuid, null: true, if_not_exists: true
  end
end
