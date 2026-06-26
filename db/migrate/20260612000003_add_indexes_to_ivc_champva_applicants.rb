# frozen_string_literal: true

class AddIndexesToIvcChampvaApplicants < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    add_index :ivc_champva_applicants, :applicant_icn, algorithm: :concurrently
    add_index :ivc_champva_applicants, %i[transaction_uuid applicant_icn],
              unique: true,
              name: 'index_ivc_champva_applicants_on_txn_uuid_and_icn',
              algorithm: :concurrently
  end
end
