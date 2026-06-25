class AddIndexClearUuidToUserVerifications < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    add_index :user_verifications, :clear_uuid, unique: true, algorithm: :concurrently unless index_exists?(:user_verifications, :clear_uuid)
  end
end
