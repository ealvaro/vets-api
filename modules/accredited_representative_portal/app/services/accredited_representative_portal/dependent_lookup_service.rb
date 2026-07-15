# frozen_string_literal: true

module AccreditedRepresentativePortal
  class DependentLookupService
    REQUIRED_AWARD_INDICATOR = 'Y'
    PROFILE_NOT_FOUND_MSG = 'Veteran profile not found'
    PID_NOT_FOUND_MSG = 'Veteran participant ID missing from profile'
    SSN_REGEX = /\A\d{9}\z/
    DATE_REGEX = /\A\d{4}-\d{2}-\d{2}\z/

    def initialize(veteran_first_name:, veteran_last_name:, veteran_ssn:, veteran_birth_date:)
      if [veteran_first_name, veteran_last_name, veteran_ssn, veteran_birth_date].any?(&:blank?)
        raise ArgumentError, 'Arguments cannot be blank'
      end

      unless veteran_birth_date.to_s.match?(DATE_REGEX)
        raise ArgumentError, 'veteran_birth_date must follow the YYYY-MM-DD format'
      end

      @veteran_first_name = veteran_first_name.to_s
      @veteran_last_name = veteran_last_name.to_s
      @veteran_ssn = validate_and_normalize_ssn(veteran_ssn)
      @veteran_birth_date = veteran_birth_date.to_s
    end

    def dependent_relationship_established?(dependent_ssn)
      raise ArgumentError, 'dependent_ssn is required' if dependent_ssn.blank?

      normalized_dependent_ssn = validate_and_normalize_ssn(dependent_ssn)

      dependents_for_veteran.any? { |dependent| dependent[:ssn] == normalized_dependent_ssn }
    end

    def dependents_for_veteran
      raise Common::Exceptions::RecordNotFound, detail: PROFILE_NOT_FOUND_MSG if veteran_profile.blank?
      raise Common::Exceptions::ResourceNotFound, detail: PID_NOT_FOUND_MSG if veteran_participant_id.blank?

      if bgs_response.present? && bgs_response[:persons].present?
        # When only one dependent exists, BGS returns a Hash instead of an Array
        # Ensure persons is always an array for consistent processing
        persons = Array.wrap(bgs_response[:persons])
        persons.select { |person| person[:award_indicator] == REQUIRED_AWARD_INDICATOR }
      else
        []
      end
    end

    private

    def veteran_profile
      @veteran_profile ||= MPI::Service.new.find_profile_by_attributes(
        first_name: @veteran_first_name, last_name: @veteran_last_name,
        ssn: @veteran_ssn, birth_date: @veteran_birth_date
      )&.profile
    end

    def veteran_participant_id
      @veteran_participant_id ||= veteran_profile&.participant_id
    end

    def bgs_service
      # Follows the same pattern as ClaimsApi::V2::ApplicationController in passing Veteran PID
      # The similar BGS::DependentService passes Veteran common_name or email and SSN instead,
      # but common_name and email are not as readily available here
      BGS::Services.new(external_uid: veteran_participant_id, external_key: veteran_participant_id)
    end

    def bgs_response
      @bgs_response ||= bgs_service.claimant.find_dependents_by_participant_id(
        veteran_participant_id,
        @veteran_ssn
      )
    end

    def validate_and_normalize_ssn(ssn)
      normalized_ssn = ssn.to_s.gsub(/\D/, '')

      raise ArgumentError, 'SSN must be a 9-digit string' unless normalized_ssn.match?(SSN_REGEX)

      normalized_ssn
    end
  end
end
