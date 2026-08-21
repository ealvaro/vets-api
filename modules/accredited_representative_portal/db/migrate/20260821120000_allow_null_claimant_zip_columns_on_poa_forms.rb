class AllowNullClaimantZipColumnsOnPoaForms < ActiveRecord::Migration[7.1]
  def change
    change_column_null :ar_power_of_attorney_forms, :claimant_zip_code_ciphertext, true
    change_column_null :ar_power_of_attorney_forms, :claimant_zip_code_bidx, true
  end
end