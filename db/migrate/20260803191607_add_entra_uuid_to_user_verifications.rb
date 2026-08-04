class AddEntraUuidToUserVerifications < ActiveRecord::Migration[7.2]
  def change
    add_column :user_verifications, :entra_uuid, :string
  end
end
