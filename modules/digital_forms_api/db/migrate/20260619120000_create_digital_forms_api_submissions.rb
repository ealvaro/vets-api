# frozen_string_literal: true

class CreateDigitalFormsApiSubmissions < ActiveRecord::Migration[7.2]
  def change
    # Shared PG enum type referenced by BOTH digital_forms_api_submissions.latest_status and
    # digital_forms_api_submission_attempts.status. Created inline before the table (deterministic
    # ordering within one migration) so the module stays at two migrations, matching the
    # bgs / claims_evidence / lighthouse precedent of a single shared enum across parent and child.
    #
    # FDF submissions are terminal once accepted or failed: the A3 poller maps a populated
    # document id -> accepted and a 404 -> failed. VBMS / manual-remediation states (as in
    # lighthouse) are a different upstream lifecycle and are intentionally NOT modeled here.
    # If a future state is ever needed, it is a cheap forward-only `ALTER TYPE ... ADD VALUE`.
    create_enum :digital_forms_api_submission_status, %w[pending accepted failed]

    create_table :digital_forms_api_submissions do |t|
      t.string :form_id, null: false, comment: 'form type of the submission, e.g. 21-686c'
      t.enum :latest_status, enum_type: 'digital_forms_api_submission_status', default: 'pending',
                             comment: 'latest status, cascaded from the most recent submission attempt'
      t.references :user_account, type: :uuid, foreign_key: true,
                                  comment: 'owning UserAccount (uuid PK); nullable for unlinked pilot rows'
      t.integer :saved_claim_id, comment: 'ID of the associated SavedClaim in vets-api, if any'
      t.string :claim_guid, comment: 'vets-api SavedClaim guid for cross-system correlation'
      t.string :bip_submission_id, comment: 'upstream BIP (Benefits Intake Platform) submission identifier'
      t.jsonb :reference_data_ciphertext, comment: 'encrypted data used to identify the resource'
      t.text :encrypted_kms_key, comment: 'KMS key used to encrypt the reference data'
      t.boolean :needs_kms_rotation, default: false, null: false,
                                     comment: 'flag for daily KmsKeyRotation::BatchInitiatorJob re-encryption'

      t.timestamps

      t.index :form_id, name: 'index_digital_forms_api_submissions_on_form_id'
      # Unique, but NULLS DISTINCT (PG default): the column is nullable to honor the shared
      # 'a Submission model' contract, so multiple NULL rows are allowed; uniqueness only binds
      # once a bip_submission_id is set (the poller's dedup key).
      t.index :bip_submission_id, unique: true,
                                  name: 'index_digital_forms_api_submissions_on_bip_submission_id'
      t.index :needs_kms_rotation, name: 'index_digital_forms_api_submissions_on_needs_kms_rotation'
    end
  end
end
