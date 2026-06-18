# frozen_string_literal: true

class CreateIvcChampvaApplicants < ActiveRecord::Migration[7.2]
  def change
    create_table :ivc_champva_applicants do |t|
      # Application linkage — joins to ivc_champva_forms.transaction_uuid
      t.uuid :transaction_uuid, null: false

      # Applicant identity (from VES ICN lookup + MPI)
      t.string :applicant_icn, null: false
      t.string :applicant_first_name
      t.string :applicant_last_name
      t.string :person_type, null: false,
               comment: 'SPONSOR or BENEFICIARY, as returned by VES ICN lookup'

      # Applicant CHAMPVA eligibility (from VES EE summary)
      t.string :ves_eligibility_status
      t.string :ves_eligibility_reason

      # Sponsor CHAMPVA eligibility (nested in VES EE summary response)
      t.string :sponsor_icn
      t.string :sponsor_eligibility_status
      t.string :sponsor_eligibility_reason

      t.boolean :eligibility_resolved, null: false, default: false

      t.timestamps
    end
  end
end
