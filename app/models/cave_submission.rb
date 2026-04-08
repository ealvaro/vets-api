# frozen_string_literal: true

class CaveSubmission < ApplicationRecord
  has_kms_key
  has_encrypted :cave_response, key: :kms_key, **lockbox_options

  belongs_to :saved_claim, optional: true

  def parsed_response
    @parsed_response ||= JSON.parse(cave_response)
  end
end
