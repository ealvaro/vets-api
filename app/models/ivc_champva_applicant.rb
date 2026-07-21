# frozen_string_literal: true

class IvcChampvaApplicant < ApplicationRecord
  validates :transaction_uuid, :applicant_icn, :person_type, presence: true

  has_kms_key
  has_encrypted :applicant_icn, key: :kms_key, **lockbox_options
  has_encrypted :applicant_first_name, key: :kms_key, **lockbox_options
  has_encrypted :applicant_last_name, key: :kms_key, **lockbox_options
  has_encrypted :sponsor_icn, key: :kms_key, **lockbox_options
end
