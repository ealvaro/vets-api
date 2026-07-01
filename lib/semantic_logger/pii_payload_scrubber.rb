# frozen_string_literal: true

require_relative '../logging/helper/data_scrubber'

# Shared payload scrubbing for PII-aware SemanticLogger formatters.
# Delegates to DataScrubber, which recursively scrubs nested hashes and arrays.
module PIIPayloadScrubber
  private

  def scrub_payload!(log)
    return unless log.payload.is_a?(Hash)

    safe_keys = Array(log.payload[:safe_keys] || log.payload['safe_keys'])
    payload = log.payload.except(:safe_keys, 'safe_keys').dup
    log.payload = Logging::Helper::DataScrubber.scrub(payload, safe_keys:)
  end
end
