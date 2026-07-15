# frozen_string_literal: true

class AddEncryptionToIvcChampvaApplicants < ActiveRecord::Migration[8.1]
  def up
    add_column_if_missing :applicant_icn_ciphertext, :text
    add_column_if_missing :applicant_first_name_ciphertext, :text
    add_column_if_missing :applicant_last_name_ciphertext, :text
    add_column_if_missing :sponsor_icn_ciphertext, :text
    add_column_if_missing :encrypted_kms_key, :text
    add_column_if_missing :needs_kms_rotation, :boolean, default: false, null: false

    remove_column_if_present :sponsor_icn
    remove_column_if_present :applicant_last_name
    remove_column_if_present :applicant_first_name
    remove_column_if_present :applicant_icn
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          'This migration drops plaintext applicant columns and cannot be safely reversed.'
  end

  private

  def add_column_if_missing(name, type, **)
    return if column_exists?(:ivc_champva_applicants, name)

    add_column :ivc_champva_applicants, name, type, **
  end

  def remove_column_if_present(name)
    return unless column_exists?(:ivc_champva_applicants, name)

    safety_assured { remove_column :ivc_champva_applicants, name }
  end
end
