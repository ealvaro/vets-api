class RemoveDslogonFromCredentialServiceProvidersDefault < ActiveRecord::Migration[7.2]
  def change
    change_column_default :client_configs, :credential_service_providers,
                          from: %w[logingov idme dslogon mhv],
                          to: %w[logingov idme mhv]
  end
end
