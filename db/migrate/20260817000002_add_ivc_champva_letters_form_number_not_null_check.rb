# frozen_string_literal: true

class AddIvcChampvaLettersFormNumberNotNullCheck < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  CONSTRAINT_NAME = 'ivc_champva_letters_form_number_null'

  def change
    add_check_constraint(
      :ivc_champva_letters,
      'form_number IS NOT NULL',
      name: CONSTRAINT_NAME,
      validate: false
    )
  end
end
