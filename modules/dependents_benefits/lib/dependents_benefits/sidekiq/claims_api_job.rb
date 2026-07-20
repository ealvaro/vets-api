# frozen_string_literal: true

require 'dependents_benefits/sidekiq/dependent_submission_job'
require 'bep/claims/service'
require 'bgs/vnp_veteran'
require 'bgs/vnp_relationships'
require 'bgs/vnp_benefit_claim'
require 'bgs/dependents'
require 'bgs/marriages'
require 'bgs/children'

module DependentsBenefits::Sidekiq
  ##
  # Submission job for dependent benefit via ClaimsAPI
  #
  class ClaimsApiJob < DependentSubmissionJob
    private

    ##
    # Submit all child claims to BGS
    #
    # @return [void]
    # @raise [DependentSubmissionError] if any claim submission fails
    def submit_claims_to_service
      # create claim via claims api
      # create contention(s) via claims api
      # create proc in BGS as 'Started'
      # send claim data to BGS
      # create claim in BGS using the above claims api claim id
      # check for successful submission
      # record status via new submission + attempt

      vbms_claim_id, = create_claim_via_claims_api

      vnp_response = bgs_service.create_proc(proc_state: 'Started')
      proc_id = vnp_response[:vnp_proc_id]
      send_data_to_vnp_tables(proc_id, vbms_claim_id)

      bgs_service.update_proc(proc_id, proc_state: 'Ready')

      DependentsBenefits::ServiceResponse.new(status: true)
    end

    ##
    # Call ClaimsAPI to create claim and contentions
    # ref: https://claims-uat.stage.bip.va.gov/swagger-ui.html#/
    #
    # @return [claim_id, contention_ids]
    def create_claim_via_claims_api
      claim_id = nil
      contention_ids = []
      # TODO: Future PR: use ClaimsAPI service to create new claim

      # TODO: Future PR: add each dependent as a contention
      # parent_claim.each_dependents do |d|
      #   contention_ids << claims_api_service.create_contention(contention_params)
      # end
      [claim_id, contention_ids]
    end

    # Sends form data to VNP tables (via BGS)
    #
    # @param proc_id [String] proc_id
    # @param vbms_claim_id [String] claim id
    # @return [void]
    def send_data_to_vnp_tables(_proc_id, _vbms_claim_id)
      generate_user_struct
      # create the participant, address, person, and phone records in VNP tables
      # upload data for each spouse, child, parent, etc
      # veteran_marriage_history, spouse_marriage_history, add_spouse
      # children_to_add, step_children, child_marriage, child_stopped_attending_school
      # loop through 'students' array in form data to capture 674 entries
      # create the claim record in VNP tables
      # update the VNP claim to reference the claim created via the claims api
    end

    # Generates an OpenStruct representing a user from stored user data
    #
    # Creates a user-like object from the veteran information stored in the
    # parent claim group's user_data JSON. Used for passing to service clients
    # that expect a user object interface.
    #
    # @return [OpenStruct] User-like object with veteran information attributes
    def generate_user_struct
      info = parent_claim.user_data['veteran_information']
      full_name = info['full_name']
      OpenStruct.new(
        first_name: full_name['first'],
        last_name: full_name['last'],
        middle_name: full_name['middle'],
        ssn: info['ssn'],
        email: info['email'],
        va_profile_email: info['va_profile_email'],
        participant_id: info['participant_id'],
        icn: info['icn'],
        uuid: info['uuid'],
        common_name: info['common_name']
      )
    rescue => e
      monitor.track_error_event('Failed to generate user struct',
                                action: 'generate_user_struct', component:, error: e.message,
                                parent_claim_id:)
      raise
    end

    # Memoized BGS service
    #
    # @return [BGS::Service] BGS service object
    def bgs_service
      @bgs_service ||= ::BGS::Service.new(generate_user_struct)
    end
  end
end
