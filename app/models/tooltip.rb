# frozen_string_literal: true

class Tooltip < ApplicationRecord
  # Maximum size for metadata JSONB field (4KB) to prevent abuse
  METADATA_MAX_BYTES = 4.kilobytes

  belongs_to :user_account, inverse_of: :tooltips

  validates :tooltip_name, presence: true, uniqueness: { scope: :user_account_id }
  validates :last_signed_in, presence: true
  validate :metadata_size_within_limit

  private

  def metadata_size_within_limit
    return if metadata.blank?

    json_size = metadata.to_json.bytesize
    return if json_size <= METADATA_MAX_BYTES

    errors.add(:metadata, "is too large (#{json_size} bytes). Maximum allowed is #{METADATA_MAX_BYTES} bytes")
  end
end
