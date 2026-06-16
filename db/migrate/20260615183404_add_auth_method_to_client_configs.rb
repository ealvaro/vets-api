# frozen_string_literal: true

class AddAuthMethodToClientConfigs < ActiveRecord::Migration[7.2]
  def change
    create_enum :client_config_auth_method, %w[pkce client_secret private_key_jwt]
    add_column :client_configs, :auth_method, :client_config_auth_method
  end
end
