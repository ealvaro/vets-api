# frozen_string_literal: true

class DropInvalidIndexIvcChampvaApplicantsNeedsKmsRotation < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    remove_index :ivc_champva_applicants,
                 name: 'index_ivc_champva_applicants_on_needs_kms_rotation',
                 algorithm: :concurrently,
                 if_exists: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
