# frozen_string_literal: true

class AddIndexFormSubmissionAttemptsBenefitsIntakeUuid < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_index :form_submission_attempts,
              :benefits_intake_uuid,
              name: 'index_form_submission_attempts_on_benefits_intake_uuid',
              algorithm: :concurrently
  end

  def down
    remove_index :form_submission_attempts,
                 name: 'index_form_submission_attempts_on_benefits_intake_uuid',
                 algorithm: :concurrently
  end
end
