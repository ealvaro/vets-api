# frozen_string_literal: true

class TooltipSerializer
  # Explicitly define the attributes to include in the response.
  # This ensures user_account_id is never exposed to clients.
  ALLOWED_ATTRIBUTES = %i[
    id
    tooltip_name
    last_signed_in
    counter
    hidden
    metadata
    created_at
    updated_at
  ].freeze

  def initialize(tooltip_or_collection)
    @resource = tooltip_or_collection
  end

  def serializable_hash(_options = nil)
    if @resource.respond_to?(:each)
      @resource.map { |tooltip| serialize_one(tooltip) }
    else
      serialize_one(@resource)
    end
  end

  alias as_json serializable_hash

  private

  def serialize_one(tooltip)
    ALLOWED_ATTRIBUTES.each_with_object({}) do |attr, hash|
      hash[attr] = tooltip.public_send(attr) if tooltip.respond_to?(attr)
    end
  end
end
