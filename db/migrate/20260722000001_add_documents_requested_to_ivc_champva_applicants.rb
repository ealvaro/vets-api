# frozen_string_literal: true

class AddDocumentsRequestedToIvcChampvaApplicants < ActiveRecord::Migration[8.1]
  def change
    add_column :ivc_champva_applicants, :documents_requested, :boolean, default: false, null: false
  end
end
