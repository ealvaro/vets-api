# frozen_string_literal: true

module AccreditedRepresentativePortal
  class DependentLookupService
    PROFILE_NOT_FOUND_MSG = 'Veteran profile not found'
    PID_NOT_FOUND_MSG = 'Veteran participant ID missing from profile'
    SSN_REGEX = /\A\d{9}\z/
    DATE_REGEX = /\A\d{4}-\d{2}-\d{2}\z/
    ICN_REGEX = /\A\d{10}V\d{6}\z/
    STATSD_PREFIX = 'ar.services.dependent_lookup_service'

    def initialize(veteran:)
      raise ArgumentError, 'veteran must be a Hash' unless veteran.is_a?(Hash)

      veteran_data = veteran.transform_keys(&:to_sym)

      @veteran_first_name = veteran_data[:first_name]&.to_s
      @veteran_last_name = veteran_data[:last_name]&.to_s
      @veteran_ssn = normalize(veteran_data[:ssn])
      @veteran_birth_date = normalize(veteran_data[:birth_date])

      validate_veteran_data
    end

    def dependents_for_veteran
      handle_missing_profile_data

      if bgs_response.present? && bgs_response[:persons].present?
        # When only one dependent exists, BGS returns a Hash instead of an Array
        # Ensure persons is always an array for consistent processing
        Array.wrap(bgs_response[:persons])
      else
        []
      end
    end

    def dependent_relationship_established?(dependent:)
      raise ArgumentError, 'dependent must be a Hash' unless dependent.is_a?(Hash)

      dependent_data = dependent.transform_keys(&:to_sym)

      @dependent_first_name = dependent_data[:first_name]&.to_s
      @dependent_last_name = dependent_data[:last_name]&.to_s
      @dependent_icn = normalize(dependent_data[:icn])
      @dependent_birth_date = normalize(dependent_data[:birth_date])

      validate_dependent_data

      dependent_match_present?
    end

    def log_dependent_relationship_state(dependent:)
      mon = Monitoring.new

      unless dependent_relationship_established?(dependent:)
        mon.track_count("#{STATSD_PREFIX}.dependent_relationship_not_established")
      end
      mon.track_count("#{STATSD_PREFIX}.dependent_profile_not_found") if dependent_profile.blank?
      mon.track_count("#{STATSD_PREFIX}.dependent_participant_id_not_found") if dependent_participant_id.blank?
    end

    private

    def veteran_profile
      @veteran_profile ||= MPI::Service.new.find_profile_by_attributes(
        first_name: @veteran_first_name, last_name: @veteran_last_name,
        ssn: @veteran_ssn, birth_date: @veteran_birth_date
      )&.profile
    end

    # SSN is only available for the Veteran, not the non-Veteran claimant
    # Therefore, using ICN as a reliable replacement for SSN for the profile lookup
    # This is written to only fetch once even if it receives no profile
    def dependent_profile
      return @dependent_profile if instance_variable_defined?(:@dependent_profile)

      @dependent_profile = MPI::Service.new.find_profile_by_identifier(
        identifier: @dependent_icn,
        identifier_type: MPI::Constants::ICN
      )&.profile
    end

    def veteran_participant_id
      @veteran_participant_id ||= veteran_profile&.participant_id
    end

    def dependent_participant_id
      @dependent_participant_id ||= dependent_profile&.participant_id
    end

    def dependent_match_present?
      # If participant ID cannot be fetched, fall back to comparing on first name, last name, and DOB
      # ClaimsApi::DependentClaimantVerificationService similarly compares names if there is no participant ID
      # DOB comparison was added for shared generational names, which can often be distinguished using DOB
      if dependent_profile.blank? || dependent_participant_id.blank?
        dependents_for_veteran.any? do |dependent|
          normalize(dependent[:first_name]) == normalize(@dependent_first_name) &&
            normalize(dependent[:last_name]) == normalize(@dependent_last_name) &&
            format_bgs_date(dependent[:date_of_birth]) == @dependent_birth_date
        end
      else
        dependents_for_veteran.any? do |dependent|
          normalize(dependent[:ptcpnt_id]) == normalize(dependent_participant_id)
        end
      end
    end

    def bgs_service
      # Follows the same pattern as ClaimsApi::DependentClaimantVerificationService in passing Veteran PID
      # The similar BGS::DependentService passes Veteran common_name or email + SSN instead,
      # but common_name and email are not as readily available here
      BGS::Services.new(external_uid: veteran_participant_id, external_key: veteran_participant_id)
    end

    def bgs_response
      @bgs_response ||= bgs_service.claimant.find_dependents_by_participant_id(
        veteran_participant_id,
        @veteran_ssn
      )
    end

    def validate_veteran_data
      if [@veteran_first_name, @veteran_last_name, @veteran_ssn, @veteran_birth_date].map(&:strip).any?(&:empty?)
        raise ArgumentError, 'Arguments cannot be blank'
      end

      unless @veteran_birth_date.match?(DATE_REGEX)
        raise ArgumentError, 'Veteran birth_date must follow the YYYY-MM-DD format'
      end

      raise ArgumentError, 'Veteran ssn must be a 9-digit string' unless @veteran_ssn.match?(SSN_REGEX)
    end

    def validate_dependent_data
      if [@dependent_first_name, @dependent_last_name,
          @dependent_icn, @dependent_birth_date].map(&:strip).any?(&:empty?)
        raise ArgumentError, 'Arguments cannot be blank'
      end

      unless @dependent_birth_date.match?(DATE_REGEX)
        raise ArgumentError, 'Dependent birth_date must follow the YYYY-MM-DD format'
      end

      raise ArgumentError, 'Dependent icn does not match expected format' unless @dependent_icn.match?(ICN_REGEX)
    end

    def handle_missing_profile_data
      raise Common::Exceptions::RecordNotFound, detail: PROFILE_NOT_FOUND_MSG if veteran_profile.blank?
      raise Common::Exceptions::ResourceNotFound, detail: PID_NOT_FOUND_MSG if veteran_participant_id.blank?
    end

    def normalize(identifier)
      identifier&.to_s&.strip&.upcase
    end

    def format_bgs_date(date)
      return nil if date.blank?

      Date.strptime(date, '%m/%d/%Y').iso8601
    end
  end
end
