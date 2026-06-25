class AddClearUuidToUserVerifications < ActiveRecord::Migration[7.2]
  def change
    add_column :user_verifications, :clear_uuid, :string, if_not_exists: true
  end
end
