class AddBenefitsIntakeUuidToBpdsSubmissions < ActiveRecord::Migration[8.1]
  def change
    add_column :bpds_submissions, :benefits_intake_uuid, :string, null: true, if_not_exists: true,
                                                                  comment: 'Lighthouse benefits_intake_uuid identifying the VBMS eFolder document, for BPDS<->VBMS correlation'
  end
end
