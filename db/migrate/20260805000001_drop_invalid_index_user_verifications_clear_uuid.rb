# frozen_string_literal: true

class DropInvalidIndexUserVerificationsClearUuid < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    remove_index :user_verifications,
                 name: 'index_user_verifications_on_clear_uuid',
                 algorithm: :concurrently,
                 if_exists: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
