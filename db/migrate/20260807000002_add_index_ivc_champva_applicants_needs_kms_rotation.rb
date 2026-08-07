# frozen_string_literal: true

class AddIndexIvcChampvaApplicantsNeedsKmsRotation < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_index :ivc_champva_applicants, :needs_kms_rotation,
              name: 'index_ivc_champva_applicants_on_needs_kms_rotation',
              algorithm: :concurrently,
              if_not_exists: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
