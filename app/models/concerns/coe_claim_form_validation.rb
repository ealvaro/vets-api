# frozen_string_literal: true

module CoeClaimFormValidation
  extend ActiveSupport::Concern

  private

  def validate_coe_rebuild_form
    validate_coe_required_fields
    validate_coe_types
    validate_full_name

    return if errors.empty?

    Rails.logger.error('SavedClaim form did not pass validation',
                       { form_id:, guid:, errors: })
  end

  def validate_coe_required_fields
    %w[fullName veteran militaryHistory loanHistory].each do |key|
      errors.add("/#{key}", 'is required') if parsed_form[key].blank?
    end
    errors.add('/privacyAgreementAccepted', 'must be accepted') if parsed_form['privacyAgreementAccepted'] != true
    mh = parsed_form['militaryHistory']
    if mh.blank? || !mh.is_a?(Hash) || mh['periodsOfService'].blank?
      errors.add('/militaryHistory/periodsOfService', 'is required')
    end
  end

  def validate_coe_types
    %w[fullName veteran militaryHistory loanHistory].each do |key|
      value = parsed_form[key]
      errors.add("/#{key}", 'must be an object') if value.present? && !value.is_a?(Hash)
    end
    periods = parsed_form.dig('militaryHistory', 'periodsOfService')
    errors.add('/militaryHistory/periodsOfService', 'must be an array') if periods.present? && !periods.is_a?(Array)
  end

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
