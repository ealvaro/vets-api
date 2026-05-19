# frozen_string_literal: true

require 'common/validations_patterns'
require 'coe/service_branch'

module CoeClaimFormValidation
  extend ActiveSupport::Concern

  include Helpers
  include DateRange
  include FullName
  include VeteranContact
  include MilitaryHistory

  MILITARY_STATUS_VALUES = %w[
    ACTIVE_DUTY VETERAN NATIONAL_GUARD_OR_RESERVES
    DISCHARGED_NATIONAL_GUARD DISCHARGED_RESERVES
  ].freeze

  COE_STATE_CODES = Common::ValidationsPatterns::COE_STATE_CODES
  DOB_PATTERN = Common::ValidationsPatterns::COE_DATE_OF_BIRTH_PATTERN
  POSTAL_CODE_PATTERN = Common::ValidationsPatterns::COE_POSTAL_CODE_PATTERN

  COE_DATE_RANGE_STRING_FORMAT_MESSAGE =
    'must be a valid date string (YYYY-MM-DD or ISO8601, e.g. 2000-01-01T00:00:00Z)'

  private

  def validate_coe_rebuild_form
    validate_coe_required_fields
    validate_coe_types
    validate_full_name
    validate_veteran_contact
    validate_military_history

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
      errors.add("/#{key}", 'must be an object') if parsed_form.key?(key) && !value.is_a?(Hash)
    end
    mh = parsed_form['militaryHistory']
    if mh.is_a?(Hash) && mh.key?('periodsOfService') && !mh['periodsOfService'].is_a?(Array)
      errors.add('/militaryHistory/periodsOfService', 'must be an array')
    end
  end
end
