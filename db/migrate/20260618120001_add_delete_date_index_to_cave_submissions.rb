class AddDeleteDateIndexToCaveSubmissions < ActiveRecord::Migration[7.2]
  # cave_submissions already exists, so the delete_date index is built CONCURRENTLY to avoid a
  # write-blocking lock (strong_migrations). disable_ddl_transaction! is required for that.
  disable_ddl_transaction!

  def change
    add_index :cave_submissions, :delete_date, algorithm: :concurrently, if_not_exists: true
  end
end
