# frozen_string_literal: true

module ClaimsApi
  module DisabilityCompensationValidationsHelper
    VALID_RESERVES_BRANCH_NAMES = %w[
      RESERVES
      AIR_NATIONAL_GUARD
      ARMY_NATIONAL_GUARD
    ].freeze

    YYYY_YYYYMM_REGEX = '^(?:19|20)[0-9][0-9]$|^(?:19|20)[0-9][0-9]-(0[1-9]|1[0-2])$'
    YYYY_MM_DD_REGEX = '^(?:[0-9]{4})-(?:0[1-9]|1[0-2])-(?:0[1-9]|[1-2][0-9]|3[0-1])$'
    DATE_STRING_FORMAT_REGEX = /^[\d-]+$/
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

    def claim_date
      @claim_date = if date_is_valid?(form_attributes['claimDate'], 'claimDate', true)
                      Date.parse(form_attributes['claimDate'])
                    else
                      Date.current
                    end
    end

    # Will check for a real date including leap year
    def date_is_valid?(date, property, is_full_date = false) # rubocop:disable Style/OptionalBooleanParameter
      return false if date.blank?

      # Convert ISO8601 timestamps to YYYY-MM-DD format
      # claim date is the only value that can be submitted with a timestamp via 526.json schema
      if date.include?('T') && property == 'claimDate'
        begin
          date = Date.parse(date).iso8601
        rescue ArgumentError
          # If parsing fails, continue with original date for normal validation flow
        end
      end

      # check for something like 'July 2017'
      unless DATE_STRING_FORMAT_REGEX =~ date || property == 'claimDate'
        collect_date_error(date, property)
        return false
      end

      return false if is_full_date && !date.match(YYYY_MM_DD_REGEX)

      return true if date.match(YYYY_YYYYMM_REGEX) # valid YYYY or YYYY-MM date

      date_y, date_m, date_d = date.split('-').map(&:to_i)

      return true if Date.valid_date?(date_y, date_m, date_d)

      # due to claimDate being an optional field with a fallback, this is the only date
      # we allow to be invalid/nil without an error
      collect_date_error(date, property) unless property == 'claimDate'

      false
    end

    def collect_date_error(date, property = '/')
      collect_error_messages(
        detail: "#{date} is not a valid date.",
        source: "data/attributes/#{property}"
      )
    end

    def errors_array
      @errors ||= []
    end

    def collect_error_messages(detail: 'Missing or invalid attribute', source: '/',
                               title: 'Unprocessable Entity', status: '422')
      errors_array.push({ detail:, source:, title:, status: })
    end
  end
end
