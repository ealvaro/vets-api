class AddIndexOnUnprocessedEducationBenefitsClaims < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :education_benefits_claims, :id,
              where: 'processed_at IS NULL',
              name: 'index_education_benefits_claims_on_unprocessed',
              algorithm: :concurrently
  end
end

