# frozen_string_literal: true

require 'date'
require 'bgs_service/person_web_service'
require 'bgs_service/redis/find_poas_service'
require 'bgs_service/benefit_claim_web_service'
require 'bgs_service/benefit_claim_service'
require 'bgs_service/e_benefits_bnft_claim_status_web_service'
require 'claims_api/dependent_claimant_update_poa_relationship_service'

module ClaimsApi
  class DependentClaimantPoaAssignmentService
    def initialize(**options)
      @poa_id = options[:poa_id]
      @poa_code = options[:poa_code]
      @veteran_participant_id = options[:veteran_participant_id]
      @dependent_participant_id = options[:dependent_participant_id]
      @veteran_file_number = options[:veteran_file_number]
      @allow_poa_access = options[:allow_poa_access]
      @allow_poa_cadd = options[:allow_poa_cadd]
      @claimant_ssn = options[:claimant_ssn]
    end

    # attempt to assign POA using person web service, and fallback to benefit claim update
    def assign_poa_to_dependent!
      return nil if assign_poa_to_dependent_via_manage_ptcpnt_rlnshp == :success

      if dependent_assignment_fallback_enabled?
        assign_with_dependent_claimant_update_poa_relationship_fallback
      else
        assign_with_legacy_update_benefit_claim_fallback
      end
    end

    private

    def assign_with_dependent_claimant_update_poa_relationship_fallback
      return nil if dependent_claimant_update_poa_relationship_service.assign_poa_to_dependent! == :success

      log_assign_to_dependent_failure(
        reason: 'Failed to assign POA via both manage_ptcpnt_rlnshp and dependent claimant update POA relationship'
      )
    end

    def assign_with_legacy_update_benefit_claim_fallback
      return nil if assign_poa_to_dependent_via_update_benefit_claim == :success

      log_assign_to_dependent_failure(
        reason: 'Failed to assign POA via both manage_ptcpnt_rlnshp and update benefit claim'
      )
    end

    def log_assign_to_dependent_failure(reason:)
      log_assignment_failure(reason:)

      raise ::Common::Exceptions::ServiceError.new(
        detail: reason
      )
    end

    def dependent_assignment_fallback_enabled?
      return @dependent_fallback_enabled unless @dependent_fallback_enabled.nil?

      @dependent_fallback_enabled = Flipper.enabled?(:claims_api_dependent_claimant_update_poa_relationship_fallback)
    end

    def dependent_claimant_update_poa_relationship_service
      ClaimsApi::DependentClaimantUpdatePoaRelationshipService.new(
        poa_id: @poa_id,
        poa_code: @poa_code,
        dependent_participant_id: @dependent_participant_id,
        veteran_file_number: @veteran_file_number,
        allow_poa_access: @allow_poa_access,
        allow_poa_cadd: @allow_poa_cadd,
        claimant_ssn: @claimant_ssn
      )
    end

    def person_web_service
      ClaimsApi::PersonWebService.new(external_uid: @dependent_participant_id,
                                      external_key: @dependent_participant_id)
    end

    def assign_poa_via_manage_ptcpnt_rlnshp_outcome
      res = person_web_service.manage_ptcpnt_rlnshp_poa(ptcpnt_id_a: @dependent_participant_id,
                                                        ptcpnt_id_b: poa_participant_id,
                                                        authzn_poa_access_ind: @allow_poa_access,
                                                        authzn_change_clmant_addrs_ind: @allow_poa_cadd)
      if manage_ptcpnt_rlnshp_poa_success?(res)
        log(message: 'POA assigned to dependent.')

        return :success
      end

      log_assignment_failure(
        reason: 'Failure to assign POA via PersonWebService.manage_ptcpnt_rlnshp_poa'
      )

      :could_not_assign_via_manage_ptcpnt_rlnshp
    end

    def log(level: :info, **rest)
      ClaimsApi::Logger.log('dependent_claimant_poa_assignment_service', level:, poa_id: @poa_id, poa_code: @poa_code,
                                                                         **rest)
    end

    def assign_poa_to_dependent_via_manage_ptcpnt_rlnshp
      assign_poa_via_manage_ptcpnt_rlnshp_outcome
    rescue ::Common::Exceptions::ServiceError => e
      if open_claims_error?(e)
        log(
          message: 'Dependent has open claims, continuing.',
          reason: fallback_attempt_reason
        )

        return :fallback_to_update_benefit_claim
      end
      log_assignment_failure(
        reason: 'Service error with Person Web Service call to assign POA via manage_ptcpnt_rlnshp'
      )

      raise e
    rescue => e
      log_assignment_failure(
        reason: 'An unknown error occurred trying to assign POA via manage_ptcpnt_rlnshp'
      )

      raise e
    end

    def iso_to_date(iso_date)
      DateTime.parse(iso_date).strftime('%m/%d/%Y')
    end

    def build_benefit_claim_update_input(claim_details:)
      claim_rcvd_dt = iso_to_date(claim_details[:claim_rcvd_dt])

      {
        file_number: @veteran_file_number,
        payee_code: claim_details[:payee_type_cd],
        date_of_claim: claim_rcvd_dt,
        claimant_ssn: @claimant_ssn,
        power_of_attorney: @poa_code,
        benefit_claim_type: benefit_claim_type(claim_details[:pgm_type_cd]),
        old_end_product_code: claim_details[:cp_claim_end_prdct_type_cd],
        new_end_product_label: claim_details[:bnft_claim_type_cd],
        old_date_of_claim: claim_rcvd_dt,
        allow_poa_access: @allow_poa_access,
        allow_poa_cadd: @allow_poa_cadd
      }
    end

    def assign_poa_to_dependent_via_update_benefit_claim
      claim_details = first_open_claim_details

      validate_claim_details_present(claim_details)

      # separate error handling to control logging and avoid logging PII from claim details.
      begin
        benefit_claim_update_input = build_benefit_claim_update_input(claim_details:)
        result = benefit_claim_service.update_benefit_claim(benefit_claim_update_input)

        if result.dig(:return, :return_message) == 'Update to Corporate was successful'
          log(message: 'POA assigned to dependent.')

          return :success

        end
        :could_not_assign_via_update_benefit_claim
      rescue => e # not logging error details to avoid logging PII, but can be added in the future if needed
        log_assignment_failure(
          reason: 'Failure to assign POA via BenefitClaimService.update_benefit_claim' \
                  "due to error class #{e.class.name}"
        )
        :could_not_assign_via_update_benefit_claim
      end
    end

    def dependent_claims
      res = e_benefits_bnft_claim_status_web_service.find_benefit_claims_status_by_ptcpnt_id(@dependent_participant_id)

      benefit_claims = Array.wrap(res&.dig(:benefit_claims_dto, :benefit_claim))

      return benefit_claims if benefit_claims.present? && benefit_claims.is_a?(Array) && benefit_claims.first.present?

      log(level: :error, message: 'Dependent claims not found in BGS')

      {}
    end

    def e_benefits_bnft_claim_status_web_service
      @e_benefits_bnft_claim_status_web_service ||= ClaimsApi::EbenefitsBnftClaimStatusWebService.new(
        external_uid: @dependent_participant_id,
        external_key: @dependent_participant_id
      )
    end

    def benefit_claim_web_service
      ClaimsApi::BenefitClaimWebService.new(external_uid: @dependent_participant_id,
                                            external_key: @dependent_participant_id)
    end

    def benefit_claim_service
      ClaimsApi::BenefitClaimService.new(external_uid: @dependent_participant_id,
                                         external_key: @dependent_participant_id)
    end

    def claim_details(claim_id)
      res = benefit_claim_web_service.find_bnft_claim(claim_id:)
      return res&.dig(:bnft_claim_dto) if res&.dig(:bnft_claim_dto).present?

      log(level: :error, message: 'Claim details not found in BGS', claim_id:)

      raise ::Common::Exceptions::ResourceNotFound
    end

    def poa_participant_id
      poa_ptcpnt = FindPOAsService.new.response.find { |combo| combo[:legacy_poa_cd] == @poa_code }

      return poa_ptcpnt&.dig(:ptcpnt_id) if poa_ptcpnt&.dig(:ptcpnt_id).present?

      log(level: :error, message: 'POA code/participant ID combo not found in BGS')

      raise ::Common::Exceptions::ResourceNotFound
    end

    def manage_ptcpnt_rlnshp_poa_success?(response)
      response.is_a?(Hash) && response.dig(:comp_id, :ptcpnt_rlnshp_type_nm) == 'Power of Attorney For'
    end

    def benefit_claim_type(pgm_type_cd)
      case pgm_type_cd
      when 'CPL'
        '1'
      when 'CPD'
        '2'
      else
        log(level: :error, message: 'Program type code not recognized', pgm_type_cd:)

        raise ::Common::Exceptions::BadRequest
      end
    end

    def first_open_claim_details
      first_open_claim = dependent_claims.find do |claim|
        claim[:phase_type] != 'Complete' && claim[:ptcpnt_vet_id] == @veteran_participant_id
      end

      if first_open_claim.present?
        claim_details(first_open_claim[:benefit_claim_id])
      else
        first_claim = benefit_claim_web_service.find_bnft_claim_by_clmant_id(
          dependent_participant_id: @dependent_participant_id
        )&.dig(:bnft_claim_dto)&.first

        first_claim_id = first_claim.present? ? first_claim[:bnft_claim_id] : nil
        first_claim_id.present? ? claim_details(first_claim_id) : {}
      end
    end

    # logging does not contain error details to avoid logging PII
    # this can be added in the future if needed, but would require refactoring to ensure no PII is logged
    def log_assignment_failure(reason:, statuses: nil)
      log_data = {
        message: 'Failed to assign POA to dependent',
        reason:
      }
      log_data[:statuses] = statuses if statuses.present?

      log(level: :error, **log_data)
    end

    def open_claims_error?(error)
      error.try(:errors)&.first&.try(:detail) == 'PtcpntIdA has open claims.'
    end

    def fallback_attempt_reason
      if dependent_assignment_fallback_enabled?
        'Failed to assign POA via manage_ptcpnt_rlnshp. ' \
          'Attempting to assign POA via DependentClaimantUpdatePoaRelationshipService.'
      else
        'Failed to assign POA via manage_ptcpnt_rlnshp. Attempting to assign POA via update benefit claim.'
      end
    end

    def dependent_claim_statuses
      claims = dependent_claims
      return [] unless claims.is_a?(Array)

      claims.pluck(:phase_type).uniq
    end

    def validate_claim_details_present(claim_details)
      if claim_details.blank?
        log_assignment_failure(
          reason: 'Dependent has no open claims',
          statuses: dependent_claim_statuses
        )

        raise ::Common::Exceptions::ServiceError.new(detail: 'Dependent has no open claims')
      end
    end
  end
end
