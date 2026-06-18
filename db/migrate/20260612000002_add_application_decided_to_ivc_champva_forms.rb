# frozen_string_literal: true

class AddApplicationDecidedToIvcChampvaForms < ActiveRecord::Migration[7.2]
  def change
    add_column :ivc_champva_forms, :application_decided, :boolean, null: false, default: false
  end
end
