# frozen_string_literal: true

require 'bgs_service/person_web_service'
require 'bgs_service/redis/find_poas_service'
require 'mpi/service'

module ClaimsApi
  class DependentClaimantVerificationService
    CLAIMANT_NOT_A_DEPENDENT_ERROR_MESSAGE =
      'The claimant is not listed as a dependent of the Veteran. ' \
      'This dependent relationship must be established in VBMS before a representative can be established.'
    POA_CODE_NOT_FOUND_ERROR_MESSAGE = 'The requested POA code could not be found.'
    DUPLICATE_PARTICIPANT_ID_ERROR_MESSAGE =
      'Claimant has multiple active Participant IDs in Master Person Index (MPI). ' \
      'Please submit an issue at ask.va.gov or call 1-800-MyVA411 (800-698-2411) for assistance.'

    attr_reader :claimant_participant_id, :claimant_ssn

    def initialize(**options)
      @veteran_participant_id = options[:veteran_participant_id]
      @claimant_first_name = options[:claimant_first_name]
      @claimant_last_name = options[:claimant_last_name]
      @claimant_participant_id = options[:claimant_participant_id]
      @claimant_ssn = nil
      @claimant_birth_date = nil
      @poa_code = options[:poa_code]
    end

    def validate_dependent_by_participant_id!
      return nil if valid_participant_dependent_combo?

      raise ::Common::Exceptions::UnprocessableEntity.new(detail: CLAIMANT_NOT_A_DEPENDENT_ERROR_MESSAGE)
    end

    def validate_poa_code_exists!
      return nil if poa_code_exists?

      raise ::Common::Exceptions::UnprocessableEntity.new(detail: POA_CODE_NOT_FOUND_ERROR_MESSAGE)
    end

    # Must be called after validate_dependent_by_participant_id!
    # so @claimant_ssn and @claimant_birth_date are populated.
    def validate_mpi_duplicate_ids!
      return unless @claimant_birth_date.present? && @claimant_ssn.present?

      profile = mpi_profile_for_dependent
      return unless profile
      return unless profile.participant_ids.size > 1

      raise ::Common::Exceptions::UnprocessableEntity.new(detail: DUPLICATE_PARTICIPANT_ID_ERROR_MESSAGE)
    end

    private

    def normalize(item)
      item.to_s.strip.upcase
    end

    def person_web_service
      ClaimsApi::PersonWebService.new(external_uid: @veteran_participant_id, external_key: @veteran_participant_id)
    end

    def matching_participant_id?(dependent)
      return false unless normalize(@claimant_participant_id) == normalize(dependent[:ptcpnt_id])

      @claimant_ssn = dependent[:ssn_nbr]
      @claimant_birth_date = dependent[:brthdy_dt]

      true
    end

    def any_matching_dependents?(dependents)
      Array.wrap(dependents).any? do |dependent|
        if @claimant_participant_id.present?
          matching_participant_id?(dependent) # let any? see true/false
        else
          matching_name?(dependent)
        end
      end
    end

    def matching_name?(dependent)
      normalized_claimant_first_name = normalize(@claimant_first_name)
      normalized_claimant_last_name  = normalize(@claimant_last_name)
      normalized_dependent_first_name = normalize(dependent[:first_nm])
      normalized_dependent_last_name  = normalize(dependent[:last_nm])

      return false if [normalized_claimant_first_name, normalized_claimant_last_name,
                       normalized_dependent_first_name, normalized_dependent_last_name].any?(&:blank?)

      if normalized_claimant_first_name == normalized_dependent_first_name &&
         normalized_claimant_last_name  == normalized_dependent_last_name
        @claimant_participant_id = dependent[:ptcpnt_id]
        @claimant_ssn = dependent[:ssn_nbr]
        @claimant_birth_date = dependent[:brthdy_dt]
        true
      else
        false
      end
    end

    def valid_participant_dependent_combo?
      return false if @veteran_participant_id.blank?

      response = person_web_service.find_dependents_by_ptcpnt_id(@veteran_participant_id)

      return false if response.nil? || response.fetch(:number_of_records, 0).to_i.zero?

      dependents = response[:dependent]

      any_matching_dependents?(dependents)
    end

    def mpi_profile_for_dependent
      MPI::Service.new.find_profile_by_attributes(
        first_name: @claimant_first_name,
        last_name: @claimant_last_name,
        birth_date: @claimant_birth_date&.to_date&.to_s,
        ssn: @claimant_ssn
      )&.profile
    rescue => e
      ClaimsApi::Logger.log('dependent_claimant_verification_service',
                            level: :warn, message: "MPI lookup failed: #{e.class}")
      nil
    end

    def poa_code_exists?
      return false if @poa_code.blank?

      response = ClaimsApi::FindPOAsService.new.response

      return false if response.nil? || !response.is_a?(Array) || response.empty?

      response.any? do |poa_participant_pair|
        normalize(poa_participant_pair[:legacy_poa_cd]) == normalize(@poa_code) &&
          poa_participant_pair[:ptcpnt_id].present?
      end
    end
  end
end
