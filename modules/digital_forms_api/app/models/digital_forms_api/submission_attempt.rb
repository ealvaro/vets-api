# frozen_string_literal: true

module DigitalFormsApi
  # A single attempt to submit / poll via the Digital Forms API (FDF / BIP).
  # Inherits the shared abstract ::SubmissionAttempt base (validates :submission presence,
  # after_create/before_update -> update_submission_status, which copies this row's `status`
  # into the parent's `latest_status`) and mixes in SubmissionAttemptEncryption for the
  # encrypted metadata / response / error_message columns.
  #
  # create_table "digital_forms_api_submission_attempts" do |t|
  #   t.bigint  "digital_forms_api_submission_id", null: false
  #   t.enum    "status", default: "pending", enum_type: "digital_forms_api_submission_status"
  #   t.jsonb   "metadata_ciphertext"
  #   t.jsonb   "response_ciphertext"
  #   t.jsonb   "error_message_ciphertext"
  #   t.text    "encrypted_kms_key"
  #   t.boolean "needs_kms_rotation", default: false, null: false
  #   t.datetime "created_at", null: false
  #   t.datetime "updated_at", null: false
  # end
  class SubmissionAttempt < ::SubmissionAttempt
    self.table_name = 'digital_forms_api_submission_attempts'

    include SubmissionAttemptEncryption

    belongs_to :submission, class_name: 'DigitalFormsApi::Submission',
                            foreign_key: :digital_forms_api_submission_id,
                            inverse_of: :submission_attempts
    has_one :saved_claim, through: :submission

    # Rails enum mirror lives only on the child (matching claims_evidence / lighthouse / bgs).
    # Values match the shared PG enum type exactly, so the base callback can copy this string
    # into the parent's latest_status (same enum domain) without coercion risk.
    enum :status, {
      pending: 'pending',
      accepted: 'accepted',
      failed: 'failed'
    }

    # Attempts still awaiting a terminal response, oldest-touched first — the poll worker (A3)
    # walks this so the least-recently-checked attempts are polled first.
    scope :pending_for_polling, -> { where(status: :pending).order(updated_at: :asc) }
  end
end
