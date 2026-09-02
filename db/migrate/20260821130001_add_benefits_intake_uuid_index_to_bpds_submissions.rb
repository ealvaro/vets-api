class AddBenefitsIntakeUuidIndexToBpdsSubmissions < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :bpds_submissions, :benefits_intake_uuid,
              where: 'benefits_intake_uuid IS NOT NULL',
              algorithm: :concurrently,
              if_not_exists: true
  end
end
