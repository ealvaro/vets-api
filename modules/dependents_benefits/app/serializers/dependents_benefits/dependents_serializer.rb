# frozen_string_literal: true

require 'dependents_benefits/helper'

module DependentsBenefits
  ##
  # Serializer for dependent information retrieved from BGS.
  # Combines person data with dependency decisions (diaries) to provide
  # information about benefit eligibility, upcoming removals, and benefit types.
  #
  # Uses JSONAPI::Serializer for JSON API compliant output.
  #
  class DependentsSerializer
    extend DependentsBenefits::Helper
    include JSONAPI::Serializer

    set_id { '' }
    set_type :dependents

    ##
    # Serializes person records with enriched dependency information.
    # Handles both single person (Hash) and multiple persons (Array) inputs.
    # Enriches each person with:
    # - upcoming_removal_date: When the person's benefits will end
    # - upcoming_removal_reason: Why the benefits will end (e.g., "Turns 18")
    # - dependent_benefit_type: The type of benefit currently received
    #
    # @return [Array<Hash>] Array of person records with dependency information
    #
    attribute :persons do |object|
      next [object[:persons]] if object[:persons].instance_of?(Hash)

      arr = object[:persons]
      diaries = object[:diaries] || []
      persons_data = object[:bip_persons_data] || []

      decisions = current_and_pending_decisions(diaries)

      arr.each do |person|
        # find diary entry and extract useful data
        upcoming_removal = person[:upcoming_removal] = upcoming_removals(decisions)[person[:ptcpnt_id]]
        if upcoming_removal
          person[:upcoming_removal_date] = parse_time(upcoming_removal[:award_effective_date])
          person[:upcoming_removal_reason] = trim_whitespace(upcoming_removal[:dependency_decision_type_description])
        end

        person[:dependent_benefit_type] = dependent_benefit_types(decisions)[person[:ptcpnt_id]]

        # find persons api data and extract useful data
        matching_person_entry = persons_data.find { |e| e['ptcpnt_id'].to_s == person[:ptcpnt_id].to_s }
        person[:date_last_verified] = matching_person_entry['last_verfd_dt'] if matching_person_entry
      end
    end
  end
end
