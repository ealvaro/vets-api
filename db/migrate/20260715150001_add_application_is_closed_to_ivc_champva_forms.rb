# frozen_string_literal: true

class AddApplicationIsClosedToIvcChampvaForms < ActiveRecord::Migration[8.1]
  def change
    add_column :ivc_champva_forms, :application_is_closed, :boolean, default: false, null: false, if_not_exists: true
  end
end
