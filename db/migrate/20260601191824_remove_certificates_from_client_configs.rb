class RemoveCertificatesFromClientConfigs < ActiveRecord::Migration[7.2]
  def change
    safety_assured do
      remove_column :client_configs, :certificates, :string, array: true, default: []
    end
  end
end
