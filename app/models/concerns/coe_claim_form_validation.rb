# frozen_string_literal: true

require 'common/validations_patterns'

module CoeClaimFormValidation
  extend ActiveSupport::Concern

  include Helpers
  include FullName
  include VeteranContact

  COE_STATE_CODES = Common::ValidationsPatterns::COE_STATE_CODES
  POSTAL_CODE_PATTERN = Common::ValidationsPatterns::COE_POSTAL_CODE_PATTERN

  private

  def validate_coe_rebuild_form
    validate_coe_required_fields
    validate_coe_types
    validate_full_name
    validate_veteran_contact

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
end
