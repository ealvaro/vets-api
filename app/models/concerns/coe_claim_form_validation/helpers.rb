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

    def validate_required_string_enum(value, fragment, allowed)
      if value.blank?
        errors.add(fragment, 'is required')
      elsif !value.is_a?(String)
        errors.add(fragment, 'must be a string')
      elsif allowed.exclude?(value)
        errors.add(fragment, 'is not a valid value')
      end
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

    def validate_booleanish_field(value, fragment)
      # Boolean false must not use `blank?` — in ActiveSupport `false.blank?` is true.
      if booleanish_value_missing?(value)
        errors.add(fragment, 'is required')
      elsif !coe_booleanish?(value)
        errors.add(fragment, 'must be true or false')
      end
    end

    def coe_form_version
      parsed_form.fetch('version', 1).to_i
    end

    def v3_coe_form?
      coe_form_version >= 3
    end

    def booleanish_value_missing?(value)
      return true if value.nil?
      return true if value.is_a?(String) && value.strip.empty?

      false
    end

    def coe_booleanish?(value)
      [true, false].include?(value) || %w[true false].include?(value.to_s.downcase)
    end

    def coe_truthy?(value)
      value == true || value.to_s.downcase == 'true'
    end

    def coe_date_string_valid?(value)
      return false if value.blank?
      return false unless value.is_a?(String)
      return true if value.match?(DOB_PATTERN)

      Time.iso8601(value)
      true
    rescue ArgumentError
      false
    end
  end
end
