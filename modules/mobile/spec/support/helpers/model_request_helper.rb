# frozen_string_literal: true

module ModelRequestHelper
  # Converts a VAProfile model or hash to a camelCase JSON string suitable
  # for use as a mobile API request body. Nil values are compacted out so
  # optional schema fields don't trigger type validation failures.
  def model_to_request_json(model_or_hash)
    hash = model_or_hash.is_a?(Hash) ? model_or_hash : model_or_hash.as_json
    hash.compact.deep_transform_keys { |k| k.to_s.camelize(:lower) }.to_json
  end
end
