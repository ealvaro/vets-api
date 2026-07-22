# frozen_string_literal: true

class AddIndexesToArRepresentativeInProgressForms < ActiveRecord::Migration[8.1]
  disable_ddl_transaction! # Required for concurrent index creation

  def change
    add_index :ar_representative_in_progress_forms,
              %i[form_id rep_user_account_id veteran_icn],
              unique: true,
              algorithm: :concurrently,
              name: 'index_ar_representative_in_progress_forms_on_composite_key'

    add_index :ar_representative_in_progress_forms,
              :rep_user_account_id,
              algorithm: :concurrently,
              name: 'index_ar_rep_in_progress_forms_on_rep_user_account_id'

    add_index :ar_representative_in_progress_forms,
              :needs_kms_rotation,
              algorithm: :concurrently,
              name: 'index_ar_rep_in_progress_forms_on_needs_kms_rotation'
  end
end
