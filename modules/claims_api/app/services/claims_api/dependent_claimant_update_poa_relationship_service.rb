# frozen_string_literal: true

require 'bgs'
require 'bgs_service/manage_representative_service'
require 'bgs_service/corporate_update_web_service'

# synchronous service module to update the POA relationship and access for dependent claimants
# using service calls from poa_updater.rb and poa_vbms_updater.rb used for veterans
module ClaimsApi
  class DependentClaimantUpdatePoaRelationshipService
    # code comes from poa_updater.rb response check
    BGS_UPDATE_RELATIONSHIP_SUCCESS_RESPONSE_CODE = 'BMOD0001'
    # code comes from poa_vbms_updater.rb response check
    BGS_UPDATE_SUCCESS_RESPONSE_CODE = 'GUIE50000'

    def initialize(**options)
      @poa_id = options[:poa_id]
      @poa_code = options[:poa_code]
      @dependent_participant_id = options[:dependent_participant_id]
      @veteran_file_number = options[:veteran_file_number]
      @allow_poa_access = options[:allow_poa_access]
      @allow_poa_c_add = options[:allow_poa_cadd] # updated name to match active_poa_update_service attribute
      @claimant_ssn = options[:claimant_ssn]
    end

    def assign_poa_to_dependent!
      # attempt to update the POA relationship for the dependent claimant
      update_relationship_response_successful?(update_poa_relationship)
      update_poa_access_successful?(update_poa_access)
      log(message: "Successfully assigned POA #{@poa_id} to dependent claimant")
      :success
    rescue => e
      # log a generic error message for failure to prevent PII
      # can possibly be scrubed in the future to log the specific error message if needed
      log_assign_to_dependent_failure(
        reason: "Failed to assign POA #{@poa_id} to dependent claimant " \
                "via backup service with error #{e&.class&.name}"
      )
      raise
    end

    private

    def update_poa_relationship
      # update the POA relationship for the dependent claimant using the BGS service
      # this toggle is enabled in prod, but keeping it for backwards compatibility
      log(message: "Updating POA relationship for dependent claimant with POA #{@poa_id}")
      if update_poa_relationship_enabled?
        manage_rep_poa_update_service.update_poa_relationship(
          pctpnt_id: @dependent_participant_id,
          file_number: @veteran_file_number,
          ssn: @claimant_ssn,
          poa_code: @poa_code
        )
      else
        bgs_ext_service.vet_record.update_birls_record(
          file_number: @veteran_file_number,
          ssn: @claimant_ssn,
          poa_code: @poa_code
        )
      end
    end

    def update_poa_access
      log(message: "Updating POA access for dependent claimant with POA #{@poa_id}")
      # this toggle is disabled in prod, but it can be enabled for testing purposes
      active_poa_update_service.update_poa_access(
        participant_id: @dependent_participant_id,
        poa_code: @poa_code,
        allow_poa_access: @allow_poa_access,
        allow_poa_c_add: @allow_poa_c_add
      )
    end

    def update_relationship_response_successful?(response)
      success = if update_poa_relationship_enabled?
                  response['dateRequestAccepted'].present?
                else
                  response[:return_code] == BGS_UPDATE_RELATIONSHIP_SUCCESS_RESPONSE_CODE
                end

      return true if success

      active_service_name = active_update_poa_relationship_service&.class&.name
      log_assign_to_dependent_failure(
        reason: "Failed to update POA relationship for the dependent in #{active_service_name}"
      )
    end

    def update_poa_access_successful?(response)
      return if response[:return_code] == BGS_UPDATE_SUCCESS_RESPONSE_CODE

      active_service_name = active_poa_update_service&.class&.name
      log_assign_to_dependent_failure(
        reason: "Failed to update POA access for the dependent in #{active_service_name}"
      )
    end

    # refactor opportunity to consolidate service call in update_poa_relationship
    def active_update_poa_relationship_service
      @active_update_poa_relationship_service ||= if update_poa_relationship_enabled?
                                                    manage_rep_poa_update_service
                                                  else
                                                    bgs_ext_service.vet_record
                                                  end
    end

    def active_poa_update_service
      @active_poa_update_service ||= if vbms_updater_uses_local_bgs?
                                       corporate_update_service
                                     else
                                       bgs_ext_service.corporate_update
                                     end
    end

    def manage_rep_poa_update_service
      ClaimsApi::ManageRepresentativeService.new(
        external_uid: @dependent_participant_id,
        external_key: @dependent_participant_id
      )
    end

    def bgs_ext_service
      BGS::Services.new(
        external_uid: @dependent_participant_id,
        external_key: @dependent_participant_id
      )
    end

    def corporate_update_service
      ClaimsApi::CorporateUpdateWebService.new(
        external_uid: @dependent_participant_id,
        external_key: @dependent_participant_id
      )
    end

    def log_assign_to_dependent_failure(reason:)
      log(level: :error, message: reason)

      raise ::Common::Exceptions::ServiceError.new(
        detail: reason
      )
    end

    def log(level: :info, **rest)
      ClaimsApi::Logger.log(
        'dependent_claimant_update_poa_relationship_service', level:, poa_id: @poa_id, poa_code: @poa_code, **rest
      )
    end

    # this Flipper is currently enabled in production
    def update_poa_relationship_enabled?
      return @update_poa_flag unless @update_poa_flag.nil?

      @update_poa_flag = Flipper.enabled?(:claims_api_use_update_poa_relationship)
    end

    # this Flipper is currently disabled in production
    def vbms_updater_uses_local_bgs?
      return @vbms_updater_flag unless @vbms_updater_flag.nil?

      @vbms_updater_flag = Flipper.enabled?(:claims_api_poa_vbms_updater_uses_local_bgs)
    end
  end
end
