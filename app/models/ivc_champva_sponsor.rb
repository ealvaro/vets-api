# frozen_string_literal: true

class IvcChampvaSponsor < ApplicationRecord
  validates :transaction_uuid, presence: true

  has_kms_key
  has_encrypted :sponsor_icn, key: :kms_key, **lockbox_options
  has_encrypted :first_name, key: :kms_key, **lockbox_options
  has_encrypted :last_name, key: :kms_key, **lockbox_options
end
