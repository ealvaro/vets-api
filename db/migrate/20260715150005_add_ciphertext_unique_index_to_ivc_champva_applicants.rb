# frozen_string_literal: true

class AddCiphertextUniqueIndexToIvcChampvaApplicants < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :ivc_champva_applicants,
              %i[transaction_uuid applicant_icn_ciphertext],
              unique: true,
              name: 'index_ivc_champva_applicants_on_txn_uuid_and_icn_ciphertext',
              algorithm: :concurrently,
              if_not_exists: true
  end
end
