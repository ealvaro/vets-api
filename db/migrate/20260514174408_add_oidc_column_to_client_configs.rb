class AddOidcColumnToClientConfigs < ActiveRecord::Migration[7.2]
  def change
    add_column :client_configs, :oidc, :boolean, default: false, null: false
  end
end
