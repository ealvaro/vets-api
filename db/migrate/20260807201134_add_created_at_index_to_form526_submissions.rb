# frozen_string_literal: true

class AddCreatedAtIndexToForm526Submissions < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    add_index :form526_submissions,
              :created_at,
              name: 'index_form526_submissions_on_created_at',
              algorithm: :concurrently
  end
end
