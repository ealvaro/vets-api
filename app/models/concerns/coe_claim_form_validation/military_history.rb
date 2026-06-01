# frozen_string_literal: true

module CoeClaimFormValidation
  module MilitaryHistory
    extend ActiveSupport::Concern

    private

    def validate_military_history
      mh = parsed_form['militaryHistory']
      return unless mh.is_a?(Hash)

      validate_required_string_enum(mh['status'], '/militaryHistory/status', MILITARY_STATUS_VALUES)
      validate_booleanish_field(mh['separatedDueToDisability'], '/militaryHistory/separatedDueToDisability')

      if v3_coe_form? && mh['status'] == 'ADSM'
        validate_booleanish_field(mh['preDischargeClaim'], '/militaryHistory/preDischargeClaim')
        validate_booleanish_field(mh['purpleHeartRecipient'], '/militaryHistory/purpleHeartRecipient')
      end

      validate_periods_of_service(mh['periodsOfService'])
    end

    def validate_periods_of_service(periods)
      return unless periods.is_a?(Array)

      errors.add('/militaryHistory/periodsOfService', 'must include at least one period of service') if periods.empty?
      periods.each_with_index { |period, i| validate_single_period_of_service(period, i) }
    end

    def validate_single_period_of_service(period, i)
      base = "/militaryHistory/periodsOfService/#{i}"
      unless period.is_a?(Hash)
        errors.add(base, 'must be an object')
        return
      end

      branch = period['serviceBranch']
      if branch.blank?
        errors.add("#{base}/serviceBranch", 'is required')
      elsif !branch.is_a?(String)
        errors.add("#{base}/serviceBranch", 'must be a string')
      elsif LGY::Constants::SERVICE_BRANCH_MAPPING.keys.exclude?(branch)
        errors.add("#{base}/serviceBranch", 'is not a valid branch')
      end

      validate_coe_date_range(period['dateRange'], base)
    end
  end
end
