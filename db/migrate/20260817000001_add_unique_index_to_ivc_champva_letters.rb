# frozen_string_literal: true

class AddUniqueIndexToIvcChampvaLetters < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :ivc_champva_letters,
              %i[ivc_champva_applicant_id form_number mail_status_date],
              unique: true,
              name: 'index_ivc_champva_letters_on_applicant_form_and_status_date',
              algorithm: :concurrently,
              if_not_exists: true
  end
end
