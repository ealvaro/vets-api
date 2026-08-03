class AddCspAndBrowserToSessionRecords < ActiveRecord::Migration[8.1]
  def change
    add_column :sign_in_session_records, :csp_type, :string
    add_column :sign_in_session_records, :browser, :string
  end
end
