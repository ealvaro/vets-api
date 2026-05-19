# frozen_string_literal: true

module CoeClaimFormValidation
  module Helpers
    extend ActiveSupport::Concern

    private

    def validate_required_string(value, fragment)
      if value.blank?
        errors.add(fragment, 'is required')
      elsif !value.is_a?(String)
        errors.add(fragment, 'must be a string')
      end
    end

    def validate_optional_string(value, fragment)
      return if value.blank?

      errors.add(fragment, 'must be a string') unless value.is_a?(String)
    end

    def validate_required_or_object_error(value, fragment)
      errors.add(fragment, 'is required') if value.blank?
      errors.add(fragment, 'must be an object') if value.present? && !value.is_a?(Hash)
    end

    def validate_postal_code(value, fragment)
      return unless value.is_a?(String) && value.present? && !value.match?(POSTAL_CODE_PATTERN)

      errors.add(fragment, 'must be a valid postal code in XXXXX or XXXXX-XXXX format')
    end

    def validate_state_code(value, fragment)
      return if !value.is_a?(String) || value.blank?

      errors.add(fragment, 'is not a valid state code') if COE_STATE_CODES.exclude?(value)
    end
  end
end
