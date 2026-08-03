class AddIndexToSessionRecordsSignedOutAt < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :sign_in_session_records, :signed_out_at, algorithm: :concurrently, if_not_exists: true, where: 'signed_out_at IS NOT NULL'
  end
end
