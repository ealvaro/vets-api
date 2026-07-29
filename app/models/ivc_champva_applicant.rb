# frozen_string_literal: true

class IvcChampvaApplicant < ApplicationRecord
  validates :transaction_uuid, :applicant_icn, :person_type, presence: true

  has_kms_key
  has_encrypted :applicant_icn, key: :kms_key, **lockbox_options
  has_encrypted :applicant_first_name, key: :kms_key, **lockbox_options
  has_encrypted :applicant_last_name, key: :kms_key, **lockbox_options
  has_encrypted :sponsor_icn, key: :kms_key, **lockbox_options

  # Returns true when VES has been queried (at least one applicant exists) and
  # every applicant for the given transaction UUID has received an eligibility
  # determination.
  def self.all_resolved_for?(transaction_uuid)
    return false if transaction_uuid.blank?

    applicants = where(transaction_uuid:)
    return false unless applicants.exists?

    applicants.where.not(eligibility_resolved: true).none?
  end
end
