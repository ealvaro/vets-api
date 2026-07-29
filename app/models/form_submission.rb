# frozen_string_literal: true

class FormSubmission < ApplicationRecord
  has_kms_key
  has_encrypted :form_data, key: :kms_key, **lockbox_options

  # form_intake_submissions used when retrying to send structured data to MMS
  # See https://va.ghe.com/software/vets-api/pull/25889
  has_many :form_intake_submissions, dependent: :destroy

  has_many :form_submission_attempts, dependent: :destroy
  belongs_to :saved_claim, optional: true
  belongs_to :user_account, optional: true

  validates :form_type, presence: true

  class << self
    def with_latest_benefits_intake_uuid(user_account)
      select('form_submissions.id, form_submissions.form_type, la.benefits_intake_uuid, form_submissions.created_at')
        .from('form_submissions')
        .joins(
          'LEFT JOIN LATERAL (' \
          '  SELECT benefits_intake_uuid' \
          '  FROM form_submission_attempts' \
          '  WHERE form_submission_id = form_submissions.id' \
          '  ORDER BY created_at DESC, id DESC' \
          '  LIMIT 1' \
          ') AS la ON true'
        )
        .order('form_submissions.id')
        .where(user_account:)
    end

    def with_form_types(form_types)
      if form_types.present?
        where(form_type: form_types)
      else
        where.not(form_type: nil)
      end
    end
  end

  def latest_attempt
    form_submission_attempts.order(created_at: :asc).last
  end

  def latest_pending_attempt
    form_submission_attempts.where(aasm_state: 'pending').order(created_at: :asc).last
  end

  def non_failure_attempt
    form_submission_attempts.where(aasm_state: %w[pending success]).first
  end
end
