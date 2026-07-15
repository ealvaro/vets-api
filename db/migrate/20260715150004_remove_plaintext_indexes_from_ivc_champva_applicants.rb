# frozen_string_literal: true

class RemovePlaintextIndexesFromIvcChampvaApplicants < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    remove_index_if_present :index_ivc_champva_applicants_on_txn_uuid_and_icn
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          'This migration removes plaintext applicant indexes and cannot be safely reversed.'
  end

  private

  def remove_index_if_present(name)
    name = name.to_s
    return unless index_exists?(:ivc_champva_applicants, name:)

    remove_index :ivc_champva_applicants, name:, algorithm: :concurrently
  end
end
