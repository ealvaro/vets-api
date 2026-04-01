class DropFlaggedVeteranRepresentativeContactData < ActiveRecord::Migration[7.2]
  def change
    drop_table :flagged_veteran_representative_contact_data, if_exists: true
  end
end
