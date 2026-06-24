# frozen_string_literal: true

module DigitalFormsApi
  # Persistence row for one submission routed through the Digital Forms API (FDF / BIP).
  # Inherits the shared abstract ::Submission base (validates :form_id, has_many
  # :submission_attempts, #latest_attempt) and mixes in SubmissionEncryption for the
  # encrypted reference_data column. latest_status is cascaded from the most recent
  # SubmissionAttempt by the base SubmissionAttempt#update_submission_status callback.
  #
  # create_table "digital_forms_api_submissions" do |t|
  #   t.string  "form_id", null: false
  #   t.enum    "latest_status", default: "pending", enum_type: "digital_forms_api_submission_status"
  #   t.uuid    "user_account_id"
  #   t.integer "saved_claim_id"
  #   t.string  "claim_guid"
  #   t.string  "bip_submission_id"
  #   t.jsonb   "reference_data_ciphertext"
  #   t.text    "encrypted_kms_key"
  #   t.boolean "needs_kms_rotation", default: false, null: false
  #   t.datetime "created_at", null: false
  #   t.datetime "updated_at", null: false
  # end
  class Submission < ::Submission
    self.table_name = 'digital_forms_api_submissions'

    include SubmissionEncryption

    # The abstract base declares a bare `has_many :submission_attempts` with no class_name or
    # foreign_key, so the subclass MUST override it with explicit options.
    has_many :submission_attempts, class_name: 'DigitalFormsApi::SubmissionAttempt',
                                   foreign_key: :digital_forms_api_submission_id,
                                   dependent: :destroy, inverse_of: :submission

    belongs_to :user_account, optional: true
    belongs_to :saved_claim, optional: true

    # Presence is guaranteed by the SubmissionHelper write path (A2), not at the model layer:
    # the shared 'a Submission model' example creates a record without a bip_submission_id, and
    # the column is nullable to honor that contract. Uniqueness (allow_nil) plus the unique DB
    # index keep the poller's lookup key unambiguous without rejecting that nil-id fixture.
    validates :bip_submission_id, uniqueness: { allow_nil: true }
  end
end
