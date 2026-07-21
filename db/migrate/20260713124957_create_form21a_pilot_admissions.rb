# frozen_string_literal: true

class CreateForm21aPilotAdmissions < ActiveRecord::Migration[8.1]
  def change
    create_enum :form21a_pilot_admission_status, %w[started submitted]

    # NOTE: Indexes are intentionally omitted here and added in a separate migration
    # (add_indexes_to_ar_form21a_pilot_admissions) per the platform's requirement that
    # index operations run concurrently, outside the DDL transaction.
    create_table :ar_form21a_pilot_admissions do |t|
      t.references :user_account,
                   null: false,
                   type: :uuid,
                   foreign_key: { to_table: :user_accounts },
                   index: false,
                   comment: 'one admission per user, ever'

      t.enum :status,
             default: 'started',
             null: false,
             enum_type: 'form21a_pilot_admission_status'

      t.datetime :submitted_at, comment: 'set when the user submits'

      # created_at doubles as the slot-granted time / Eastern month bucket for the monthly count query
      t.timestamps null: false

      # A submitted admission must carry its submission timestamp; guards against the inconsistent
      # state where status is 'submitted' but submitted_at is NULL.
      t.check_constraint "status <> 'submitted' OR submitted_at IS NOT NULL",
                         name: 'check_ar_form21a_pilot_admissions_submitted_at_present'
    end
  end
end
