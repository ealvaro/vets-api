# frozen_string_literal: true

class AddIndexesToArRepresentativeInProgressForms < ActiveRecord::Migration[8.1]
  disable_ddl_transaction! # Required for concurrent index creation

  def up
    # Clean up any INVALID indexes left behind by a prior failed
    # CREATE INDEX CONCURRENTLY attempt. Wrapped in safety_assured because
    # strong_migrations can't inspect raw execute calls; DROP INDEX
    # CONCURRENTLY IF EXISTS is safe (non-blocking, no-op if absent).
    safety_assured do
      execute 'DROP INDEX CONCURRENTLY IF EXISTS index_ar_representative_in_progress_forms_on_composite_key'
      execute 'DROP INDEX CONCURRENTLY IF EXISTS index_ar_rep_in_progress_forms_on_rep_user_account_id'
      execute 'DROP INDEX CONCURRENTLY IF EXISTS index_ar_rep_in_progress_forms_on_needs_kms_rotation'
    end

    add_index :ar_representative_in_progress_forms,
              %i[form_id rep_user_account_id veteran_icn],
              unique: true,
              algorithm: :concurrently,
              if_not_exists: true,
              name: 'index_ar_representative_in_progress_forms_on_composite_key'

    add_index :ar_representative_in_progress_forms,
              :rep_user_account_id,
              algorithm: :concurrently,
              if_not_exists: true,
              name: 'index_ar_rep_in_progress_forms_on_rep_user_account_id'

    add_index :ar_representative_in_progress_forms,
              :needs_kms_rotation,
              algorithm: :concurrently,
              if_not_exists: true,
              name: 'index_ar_rep_in_progress_forms_on_needs_kms_rotation'
  end
end
