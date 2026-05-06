# frozen_string_literal: true

class AddAcceptanceModeColumnsToVeteranOrganizations < ActiveRecord::Migration[7.2]
  def change
    safety_assured do
      add_column :veteran_organizations, :primary_org_acceptance_mode, :string, default: 'no_acceptance', null: false
      add_column :veteran_organizations, :default_new_rep_acceptance_mode, :string, default: 'no_acceptance', null: false

      add_check_constraint :veteran_organizations,
                           "primary_org_acceptance_mode IN ('any_request', 'self_only', 'no_acceptance')",
                           name: 'check_veteran_orgs_primary_org_acceptance_mode'
      add_check_constraint :veteran_organizations,
                           "default_new_rep_acceptance_mode IN ('any_request', 'self_only', 'no_acceptance')",
                           name: 'check_veteran_orgs_default_new_rep_acceptance_mode'
    end
  end
end
