# frozen_string_literal: true

module CoeClaimFormValidation
  module FullName
    extend ActiveSupport::Concern

    private

    def validate_full_name
      name = parsed_form['fullName']
      return unless name.is_a?(Hash)

      %w[first last].each { |part| validate_full_name_part(name, part, required: true) }
      %w[middle suffix].each { |part| validate_full_name_part(name, part, required: false) }
    end

    def validate_full_name_part(name, part, required:)
      value = name[part]
      fragment = "/fullName/#{part}"
      if value.blank?
        errors.add(fragment, 'is required') if required
        return
      end
      errors.add(fragment, 'must be a string') unless value.is_a?(String)
      return unless value.is_a?(String) && value.length > 30

      errors.add(fragment, 'must be 30 characters or less')
    end
  end
end
