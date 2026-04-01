# frozen_string_literal: true

module ClaimsApi
  module DisabilityCompensationValidationsHelper
    VALID_RESERVES_BRANCH_NAMES = %w[
      RESERVES
      AIR_NATIONAL_GUARD
      ARMY_NATIONAL_GUARD
    ].freeze

    VALID_NEW_DISABILITY_NAME_REGEX = %r{^(?!.* {2})[a-zA-Z0-9',. /()-]+$}

    # Validates disability name format for NEW disabilities
    # Regex pattern from FES: ^(?!.* {2})[a-zA-Z0-9',. /()-]+$
    def valid_disability_name_for_new_action?(name, action_type)
      return true unless action_type == 'NEW'
      return false if name.blank?

      name.match?(VALID_NEW_DISABILITY_NAME_REGEX)
    end

    def eligible_for_future_end_date?(max_period, service_periods)
      most_recent_service_branch_is_reserves_or_guard?(max_period) && past_service_period?(service_periods)
    end

    def most_recent_service_branch_is_reserves_or_guard?(max_period)
      most_recent_service_branch_name = max_period['serviceBranch']&.upcase&.gsub(/\s+/, '_')
      return false if most_recent_service_branch_name.blank?

      VALID_RESERVES_BRANCH_NAMES.any? { |name| most_recent_service_branch_name.include?(name) }
    end

    def past_service_period?(service_periods)
      return false if service_periods.blank?

      service_periods.any? do |sp|
        end_date = sp['activeDutyEndDate']
        next false if end_date.blank?

        Date.parse(end_date) <= Time.zone.today.end_of_day
      end
    end

    def flatten_disabilities(disabilities_array)
      disabilities_array.flat_map do |disability|
        primary_disability = disability.dup
        secondaries = primary_disability.delete('secondaryDisabilities') || []

        list = []
        list << primary_disability unless primary_disability['disabilityActionType'] == 'NONE'
        list.concat(secondaries)

        list
      end
    end
  end
end
