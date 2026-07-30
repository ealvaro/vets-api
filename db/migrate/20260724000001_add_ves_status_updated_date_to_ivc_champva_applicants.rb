# frozen_string_literal: true

class AddVesStatusUpdatedDateToIvcChampvaApplicants < ActiveRecord::Migration[8.1]
  def change
    add_column :ivc_champva_applicants, :ves_status_updated_date, :date
  end
end
