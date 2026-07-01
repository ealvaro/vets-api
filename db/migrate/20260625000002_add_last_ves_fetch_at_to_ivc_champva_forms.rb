# frozen_string_literal: true

class AddLastVesFetchAtToIvcChampvaForms < ActiveRecord::Migration[7.2]
  def change
    add_column :ivc_champva_forms, :last_ves_fetch_at, :datetime
  end
end
