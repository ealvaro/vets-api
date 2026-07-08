class AddWebauthnCredentialForeignKeyToUserVerifications < ActiveRecord::Migration[8.1]
  def change
    add_foreign_key :user_verifications, :sign_in_webauthn_credentials, column: :webauthn_credential_id,
                                                                        validate: false, if_not_exists: true
  end
end
