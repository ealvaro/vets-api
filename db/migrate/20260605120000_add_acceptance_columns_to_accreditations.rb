# frozen_string_literal: true

class AddAcceptanceColumnsToAccreditations < ActiveRecord::Migration[7.2]
  def change
    safety_assured do
      add_column :accreditations, :acceptance_mode, :string, default: 'no_acceptance', null: false
      add_column :accreditations, :deactivated_at, :datetime

      add_check_constraint :accreditations,
                           "acceptance_mode IN ('any_request', 'self_only', 'no_acceptance')",
                           name: 'check_accreditations_acceptance_mode'
    end
  end
end
