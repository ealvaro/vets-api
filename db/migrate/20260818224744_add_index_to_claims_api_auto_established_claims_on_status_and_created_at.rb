class AddIndexToClaimsApiAutoEstablishedClaimsOnStatusAndCreatedAt < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :claims_api_auto_established_claims, [:status, :created_at],
               algorithm: :concurrently,
               name: 'index_claims_api_auto_established_claims_on_status_created_at'
  end
end
