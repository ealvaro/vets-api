# frozen_string_literal: true

require_relative 'pii_payload_scrubber'

# Colorized SemanticLogger output with PII scrubbing for local development.
#
# USAGE:
#   Rails.logger.info('User action')  # String - passes through unchanged
#   Rails.logger.info('User action', { ssn: '123-45-6789' })  # ssn -> [REDACTED]
#   Rails.logger.info('User action', { ssn: '123', safe_keys: [:ssn] })  # ssn preserved
#
class PIIFilteringColorFormatter < SemanticLogger::Formatters::Color
  include PIIPayloadScrubber

  def call(log, logger)
    scrub_payload!(log)
    super
  end
end
