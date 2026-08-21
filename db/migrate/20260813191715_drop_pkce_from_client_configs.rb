class DropPkceFromClientConfigs < ActiveRecord::Migration[8.1]
  def change
    safety_assured { remove_column :client_configs, :pkce, :boolean }
  end
end
