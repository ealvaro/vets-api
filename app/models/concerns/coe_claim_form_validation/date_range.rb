# frozen_string_literal: true

module CoeClaimFormValidation
  COE_DATE_RANGE_STRING_FORMAT_MESSAGE =
    'must be a valid date string (YYYY-MM-DD or ISO8601, e.g. 2000-01-01T00:00:00Z)'

  module DateRange
    extend ActiveSupport::Concern

    private

    def validate_coe_date_range(dr, base)
      prefix = "#{base}/dateRange"
      return unless validate_coe_date_range_container(dr, prefix)

      validate_coe_date_range_from(dr['from'], "#{prefix}/from")
      validate_coe_date_range_optional_to(dr, prefix)
      validate_coe_date_range_chronology(dr, prefix)
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

      errors.add(fragment, COE_DATE_RANGE_STRING_FORMAT_MESSAGE)
    end

    def validate_coe_date_range_optional_to(dr, prefix)
      to = dr['to']
      return unless dr.key?('to') && to.present?

      if !to.is_a?(String)
        errors.add("#{prefix}/to", 'must be a string')
      elsif !coe_date_string_valid?(to)
        errors.add("#{prefix}/to", COE_DATE_RANGE_STRING_FORMAT_MESSAGE)
      end
    end

    def validate_coe_date_range_chronology(dr, prefix)
      from = dr['from']
      to = dr['to']
      return unless from.is_a?(String) && to.is_a?(String)
      return unless coe_date_string_valid?(from) && coe_date_string_valid?(to)
      return unless Date.iso8601(to) < Date.iso8601(from)

      errors.add("#{prefix}/to", 'must be on or after from')
    end
  end
end
