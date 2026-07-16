# frozen_string_literal: true

class AddNeedsKmsRotationIndexToIvcChampvaSponsors < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :ivc_champva_sponsors,
              :needs_kms_rotation,
              name: 'index_ivc_champva_sponsors_on_needs_kms_rotation_true',
              where: 'needs_kms_rotation = true',
              algorithm: :concurrently,
              if_not_exists: true
  end
end
