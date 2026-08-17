class AddUserAccountIdToHealthCareApplications < ActiveRecord::Migration[8.1]
  def change
    add_column :health_care_applications, :user_account_id, :uuid
  end
end
