# frozen_string_literal: true

class AddNeedsKmsRotationIndexToIvcChampvaApplicants < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :ivc_champva_applicants,
              :needs_kms_rotation,
              algorithm: :concurrently,
              if_not_exists: true
  end
end
