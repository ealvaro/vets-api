# frozen_string_literal: true

class AddIndexToIvcChampvaLettersOnApplicantId < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :ivc_champva_letters,
              :ivc_champva_applicant_id,
              algorithm: :concurrently,
              if_not_exists: true
  end
end
