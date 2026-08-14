# frozen_string_literal: true

class AddCompositeIndexClaimsEvidenceApiSubmissions < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    # find_or_create_by always queries all three columns together; composite covers
    # that lookup and also serves saved_claim_id-only prefix scans.
    add_index :claims_evidence_api_submissions,
              %i[saved_claim_id persistent_attachment_id form_id],
              name: 'idx_claims_evidence_submissions_on_claim_attachment_form',
              algorithm: :concurrently
  end

  def down
    remove_index :claims_evidence_api_submissions,
                 name: 'idx_claims_evidence_submissions_on_claim_attachment_form',
                 algorithm: :concurrently
  end
end
