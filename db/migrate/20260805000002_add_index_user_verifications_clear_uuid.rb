# frozen_string_literal: true

class AddIndexUserVerificationsClearUuid < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  # Before this migration, verify no duplicate clear_uuid values exist:
  #   SELECT clear_uuid, COUNT(*) FROM user_verifications
  #   WHERE clear_uuid IS NOT NULL
  #   GROUP BY clear_uuid HAVING COUNT(*) > 1;
  def up
    add_index :user_verifications, :clear_uuid,
              name: 'index_user_verifications_on_clear_uuid',
              unique: true,
              algorithm: :concurrently,
              if_not_exists: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
