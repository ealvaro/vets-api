# frozen_string_literal: true

class AddNeedsKmsRotationToIvcChampvaSponsors < ActiveRecord::Migration[8.1]
  def change
    add_column :ivc_champva_sponsors, :needs_kms_rotation, :boolean, default: false, null: false, if_not_exists: true
  end
end
