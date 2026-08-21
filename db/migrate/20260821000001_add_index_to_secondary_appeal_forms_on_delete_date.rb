# frozen_string_literal: true

class AddIndexToSecondaryAppealFormsOnDeleteDate < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_index :secondary_appeal_forms, :delete_date,
              name: 'index_secondary_appeal_forms_on_delete_date',
              algorithm: :concurrently
  end

  def down
    remove_index :secondary_appeal_forms, name: 'index_secondary_appeal_forms_on_delete_date',
                 algorithm: :concurrently, if_exists: true
  end
end
