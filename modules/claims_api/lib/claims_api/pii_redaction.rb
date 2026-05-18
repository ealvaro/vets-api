# frozen_string_literal: true

module ClaimsApi
  module PiiRedaction
    # Spring @Valid errors echo rejected field values as: field = 'value':
    # FES Java uses nullSafeConciseToString() which does not escape quotes,
    # and always wraps values in single quotes (never double quotes).
    # This pattern matches the quoted value so it can be redacted.
    SPRING_FIELD_VALUE_PATTERN = Regexp.new("= '[^']*':")
    SPRING_FIELD_VALUE_REPLACEMENT = "= '[REDACTED]':"

    module_function

    def sanitize_error_detail_pii(response)
      return response.to_s unless response.is_a?(Hash)

      sanitized = response.deep_dup
      errors = Array.wrap(sanitized.dig(:data, :errors) || sanitized[:errors])
      errors.each do |error|
        next unless error.is_a?(Hash)

        if error.key?(:source)
          # FES validator errors include a source pointer that identifies the field —
          # redact detail since it may echo user-submitted values
          error[:detail] = '[REDACTED]'
        elsif error[:detail].is_a?(String)
          error[:detail] = error[:detail].gsub(
            SPRING_FIELD_VALUE_PATTERN, SPRING_FIELD_VALUE_REPLACEMENT
          )
        end
      end

      sanitized.to_s
    end
  end
end
