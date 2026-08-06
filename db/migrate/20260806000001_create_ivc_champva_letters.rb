# frozen_string_literal: true

class CreateIvcChampvaLetters < ActiveRecord::Migration[8.1]
  def change
    create_table :ivc_champva_letters do |t|
      # Links to ivc_champva_applicants.id (1 applicant : many letters).
      # Indexed in a follow-up migration so this create runs without a long lock.
      t.bigint :ivc_champva_applicant_id, null: false

      # From VES mailCorrespondences[].letterTemplate
      t.string :letter_name
      t.string :form_number

      # From VES mailCorrespondences[]
      t.string :mail_status
      t.datetime :mail_status_date

      t.timestamps
    end
  end
end
