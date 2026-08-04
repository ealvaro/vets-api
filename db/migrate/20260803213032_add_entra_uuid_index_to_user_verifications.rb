class AddEntraUuidIndexToUserVerifications < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    add_index :user_verifications, :entra_uuid, unique: true, algorithm: :concurrently,
                                                where: 'entra_uuid IS NOT NULL'
  end
end
