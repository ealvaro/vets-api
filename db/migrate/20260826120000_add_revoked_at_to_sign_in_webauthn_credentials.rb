# frozen_string_literal: true

class AddRevokedAtToSignInWebauthnCredentials < ActiveRecord::Migration[8.1]
  def change
    add_column :sign_in_webauthn_credentials, :revoked_at, :datetime
  end
end
