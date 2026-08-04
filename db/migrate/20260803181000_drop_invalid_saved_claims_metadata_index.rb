# frozen_string_literal: true

class DropInvalidSavedClaimsMetadataIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  INDEX_NAME = 'idx_saved_claims_partial_metadata_like_error_and_type'

  # PgHero flagged this index as invalid. Drop it explicitly first to isolate
  # failures and keep rollout behavior simple.
  def up
    remove_index :saved_claims,
                 name: INDEX_NAME,
                 algorithm: :concurrently,
                 if_exists: true
  end

  def down
    add_index :saved_claims, [:id, :type],
              name: INDEX_NAME,
              where: "(metadata LIKE '%error%')",
              algorithm: :concurrently,
              if_not_exists: true
  end
end
