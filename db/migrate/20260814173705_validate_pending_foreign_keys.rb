class ValidatePendingForeignKeys < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!  # required — VALIDATE CONSTRAINT can't run inside a transaction block with other DDL

  def up
    validate_fk_if_exists(:schema_contract_validations, 'user_accounts')
    validate_fk_if_exists(:saved_claim_groups, 'saved_claims', column: 'parent_claim_id')
    validate_fk_if_exists(:saved_claim_groups, 'saved_claims')
    validate_fk_if_exists(:user_verifications, 'sign_in_webauthn_credentials', column: 'webauthn_credential_id')
  end

  def down
    # no-op
  end

  private

  def validate_fk_if_exists(from_table, to_table, column: nil)
    options = column ? { column: column } : {}
    return unless foreign_key_exists?(from_table, to_table, **options)

    validate_foreign_key from_table, to_table, **options
  end
end
