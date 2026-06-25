class RemoveMobileUsers < ActiveRecord::Migration[7.2]
  def change
    drop_table :mobile_users, if_exists: true
  end
end
