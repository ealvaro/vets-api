# frozen_string_literal: true

class ValidateIvcChampvaLettersFormNumberNotNull < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  CONSTRAINT_NAME = 'ivc_champva_letters_form_number_null'

  def up
    validate_check_constraint :ivc_champva_letters, name: CONSTRAINT_NAME
    change_column_null :ivc_champva_letters, :form_number, false
    remove_check_constraint :ivc_champva_letters, name: CONSTRAINT_NAME
  end

  def down
    add_check_constraint(
      :ivc_champva_letters,
      'form_number IS NOT NULL',
      name: CONSTRAINT_NAME,
      validate: false
    )
    change_column_null :ivc_champva_letters, :form_number, true
  end
end
