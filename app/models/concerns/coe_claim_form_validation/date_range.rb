# frozen_string_literal: true

module CoeClaimFormValidation
  module DateRange
    extend ActiveSupport::Concern

    private

    def validate_coe_date_range(dr, base)
      prefix = "#{base}/dateRange"
      return unless validate_coe_date_range_container(dr, prefix)

      validate_coe_date_range_from(dr['from'], "#{prefix}/from")
      validate_coe_date_range_optional_to(dr, prefix)
      validate_coe_date_range_chronology(dr, prefix) if date_range_chronology_validation?
    end

    def validate_coe_date_range_container(dr, prefix)
      if dr.blank?
        errors.add(prefix, 'is required')
        return false
      end
      unless dr.is_a?(Hash)
        errors.add(prefix, 'must be an object')
        return false
      end

      true
    end

    def validate_coe_date_range_from(from, fragment)
      errors.add(fragment, 'is required') if from.blank?
      if from.present? && !from.is_a?(String)
        errors.add(fragment, 'must be a string')
        return
      end
      return unless from.present? && !coe_date_string_valid?(from)

      errors.add(fragment, coe_invalid_date_message)
    end

    def validate_coe_date_range_optional_to(dr, prefix)
      to = dr['to']
      return unless dr.key?('to') && to.present?

      if !to.is_a?(String)
        errors.add("#{prefix}/to", 'must be a string')
      elsif !coe_date_string_valid?(to)
        errors.add("#{prefix}/to", coe_invalid_date_message)
      end
    end

    def coe_invalid_date_message
      if date_range_chronology_validation?
        COE_DATE_RANGE_STRING_FORMAT_MESSAGE
      else
        'must be a valid date'
      end
    end

    def date_range_chronology_validation?
      CoeClaimFormValidation.const_defined?(:COE_DATE_RANGE_STRING_FORMAT_MESSAGE, false)
    end

    def validate_coe_date_range_chronology(dr, prefix)
      from = dr['from']
      to = dr['to']
      return unless from.is_a?(String) && to.is_a?(String)
      return unless coe_date_string_valid?(from) && coe_date_string_valid?(to)
      return unless Time.iso8601(to) < Time.iso8601(from)

      errors.add("#{prefix}/to", 'must be on or after from')
    end
  end
end
