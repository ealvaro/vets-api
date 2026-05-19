class AddClientSecretDigestToClientConfigs < ActiveRecord::Migration[7.2]
  def change
    add_column :client_configs, :client_secret_digest, :string
  end
end
