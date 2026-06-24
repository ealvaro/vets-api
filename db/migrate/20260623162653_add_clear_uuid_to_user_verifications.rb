class AddClearUuidToUserVerifications < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    add_column :user_verifications, :clear_uuid, :string
    add_index :user_verifications, :clear_uuid, unique: true, algorithm: :concurrently
  end
end
