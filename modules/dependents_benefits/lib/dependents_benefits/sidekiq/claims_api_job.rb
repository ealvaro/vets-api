# frozen_string_literal: true

require 'dependents_benefits/sidekiq/dependent_submission_job'
require 'bep/claims/service'
require 'bgs/vnp_veteran'
require 'bgs/vnp_relationships'
require 'bgs/vnp_benefit_claim'
require 'bgs/dependents'
require 'bgs/marriages'
require 'bgs/children'
require 'bgs/student_school'
require 'bgs/dependent_higher_ed_attendance'
require 'bgs/person_cache'

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
      # Check that a previous submission didn't already succeed
      # Create claim via claims api
      # Create contention(s) via claims api
      # Create proc in BGS as 'Started'
      # Send claim data to BGS
      # Create claim in BGS using the above claims api claim id
      # Record status via new submission + attempt
      submission = find_or_create_form_submission(parent_claim)
      return DependentsBenefits::ServiceResponse.new(status: true) if submission_previously_succeeded?(submission)

      submission_attempt = create_form_submission_attempt(submission)

      is_674_only = parent_claim.submittable_674? && !parent_claim.submittable_686?

      claim_type = is_674_only ? '130SCHATTEBN' : '130DPNEBNADJ'
      vbms_claim_id = create_claim_via_claims_api(claim_type)
      create_contentions_via_claims_api(vbms_claim_id) unless is_674_only

      vnp_response = bgs_service.create_proc(proc_state: 'Started')
      proc_id = vnp_response[:vnp_proc_id]
      send_data_to_vnp_tables(proc_id, vbms_claim_id, claim_type)

      bgs_service.update_proc(proc_id, proc_state: 'Ready')

      mark_submission_attempt_succeeded(submission_attempt)
      DependentsBenefits::ServiceResponse.new(status: true)
    rescue => e
      monitor.track_error_event("Submission attempt failure in #{self.class}",
                                action: 'claim.error', component:, error: e.message,
                                parent_claim_id: parent_claim.id)
      mark_submission_attempt_failed(submission_attempt, e)
      raise # re-raise so super class can catch and call handle_job_failure
    end

    ##
    # Call ClaimsAPI to create claim
    # ref: https://claims-uat.stage.bip.va.gov/swagger-ui.html#/
    #
    # @return [claim_id]
    def create_claim_via_claims_api(claim_type)
      response = claims_api_service.create_claim(create_claim_params(claim_type))
      response['claim_id']
    rescue => e
      monitor.track_error_event('Failed to create claim via claims api',
                                action: 'create_claim', component:, error: e.message,
                                parent_claim_id:)
      raise
    end

    ##
    # Params needed for ClaimsAPI to create claim
    # ref: https://claims-uat.stage.bip.va.gov/swagger-ui.html#/
    #
    # @return [Hash]
    def create_claim_params(claim_type_code)
      user = generate_user_struct
      {
        serviceTypeCode: 'CP',
        programTypeCode: 'CPL',
        benefitClaimTypeCode: claim_type_code,
        claimant: {
          participantId: user.participant_id
        },
        veteran: {
          participantId: user.participant_id,
          firstName: user.first_name,
          lastName: user.last_name
        },
        dateOfClaim: parent_claim.created_at.iso8601,
        tempStationOfJurisdiction: 281,
        submtrRoleTypeCd: 'VBA',
        submtrApplcnTypeCd: 'VBMS'
      }
    end

    ##
    # Call ClaimsAPI to create contentions
    # ref: https://claims-uat.stage.bip.va.gov/swagger-ui.html#/
    #
    # @return [contention_ids]
    def create_contentions_via_claims_api(claim_id)
      contentions = []
      application_data = parent_claim.parsed_form['dependents_application']

      # fortunately these are all formatted similarly so we can consolidate parsing logic
      %w[student_information deaths children_to_add step_children child_marriage
         child_stopped_attending_school].each do |key|
        (application_data[key] || []).each do |data|
          contentions << create_contention_params(format_full_name(data['full_name']))
        end
      end

      # divorce
      if (divorce_name = application_data.dig('report_divorce', 'full_name')).present?
        contentions << create_contention_params(format_full_name(divorce_name))
      end

      # marriage
      if (marriage_name = application_data.dig('spouse_information', 'full_name')).present?
        contentions << create_contention_params(format_full_name(marriage_name))
      end

      response = claims_api_service.create_contentions(claim_id, { createContentions: contentions })
      response['contention_ids']
    rescue => e
      monitor.track_error_event('Failed to create contentions via claims api', action: 'create_contentions', component:,
                                                                               error: e.message, parent_claim_id:)
      raise
    end

    # Params for creating a contention via the Claims API
    #
    # @param name [String]name
    # @return [Hash]
    def create_contention_params(name)
      {
        medicalInd: false,
        contentionTypeCode: 'NEW',
        classificationType: 8925,
        claimantText: "Dependency claim for #{name}",
        beginDate: parent_claim.created_at.iso8601
      }
    end

    # Sends form data to VNP tables (via BGS)
    #
    # @param proc_id [String] proc_id
    # @param vbms_claim_id [String] claim id
    # @return [void]
    def send_data_to_vnp_tables(proc_id, vbms_claim_id, claim_type)
      user = generate_user_struct

      send_vnp_proc_forms(proc_id)

      veteran = ::BGS::VnpVeteran.new(proc_id:, payload: normalized_data, user:, claim_type:).create

      send_vnp_relationship(proc_id, veteran)

      # create the claim record in VNP tables
      vnp_benefit_claim = ::BGS::VnpBenefitClaim.new(proc_id:, veteran:, user:)
      vnp_benefit_claim_record = vnp_benefit_claim.create

      # update the VNP claim to reference the claim created via the claims api
      vnp_benefit_claim.update({
                                 claim_type_code: claim_type,
                                 benefit_claim_id: vbms_claim_id,
                                 program_type_code: 'CPL',
                                 status_type_code: 'PEND'
                               }, vnp_benefit_claim_record)
    rescue => e
      monitor.track_error_event('Failed to send data to VNP tables',
                                action: 'send_vnp_data', component:, error: e.message,
                                parent_claim_id:)
      raise
    end

    # Send create_proc_form data to VNP tables
    def send_vnp_proc_forms(proc_id)
      if parent_claim.submittable_686?
        bgs_service.create_proc_form(proc_id,
                                     ::DependentsBenefits::ADD_REMOVE_DEPENDENT.downcase)
      end
      if parent_claim.submittable_674?
        bgs_service.create_proc_form(proc_id,
                                     ::DependentsBenefits::SCHOOL_ATTENDANCE_APPROVAL)
      end
    end

    # Send relationship data to VNP tables
    def send_vnp_relationship(proc_id, veteran)
      user = generate_user_struct
      person_cache = ::BGS::PersonCache.new(user)
      # upload data for each spouse, child, parent, etc
      # report_death, report_divorce
      dependents = ::BGS::Dependents.new(proc_id:, payload: normalized_data, user:, person_cache:).create_all

      # veteran_marriage_history, spouse_marriage_history, add_spouse
      marriages = ::BGS::Marriages.new(proc_id:, payload: normalized_data, user:, person_cache:).create_all

      # children_to_add, step_children, child_marriage, child_stopped_attending_school
      children = ::BGS::Children.new(proc_id:, payload: normalized_data, user:, person_cache:).create_all

      # student_information (i.e. 674-related children 18-23)
      students = (normalized_data.dig('dependents_application', 'student_information') || []).map do |student|
        result = ::BGS::DependentHigherEdAttendance.new(proc_id:, payload: normalized_data, user:, student:,
                                                        person_cache:).create
        ::BGS::StudentSchool.new(
          proc_id:, vnp_participant_id: result[:vnp_participant_id], payload: normalized_data,
          user:, student:
        ).create
        result
      end

      ::BGS::VnpRelationships.new(
        proc_id:, veteran:, user:,
        dependents: dependents + marriages + children[:dependents] + students,
        step_children: children[:step_children]
      ).create_all
    end

    # Normalizes the form data by handling special characters
    #
    # @return [Hash] normalized form data object
    def normalized_data
      @normalized_data ||= ::BGS::Job.new.normalize_names_and_addresses!(parent_claim.parsed_form)
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

    ##
    # Finds or creates a form submission record
    #
    # @param claim [SavedClaim] The claim to find or create a submission for
    # @return [FormSubmission] The submission record
    def find_or_create_form_submission(claim)
      FormSubmission.create_with(
        form_type: claim.form_id,
        saved_claim: claim,
        user_account_id: claim.user_account_id
      ).find_or_create_by(form_type: claim.form_id, saved_claim_id: claim.id)
    end

    ##
    # Check if a submission has already succeeded
    #
    # @param submission [FormSubmission] The form submission record to check
    # @return [Boolean] true if submission has a non-failure attempt
    def submission_previously_succeeded?(submission)
      submission&.non_failure_attempt.present?
    end

    ##
    # Generates a new form submission attempt record
    #
    # @param submission [FormSubmission] The submission to create an attempt for
    # @return [FOrmSubmissionAttempt] The newly created attempt record
    def create_form_submission_attempt(submission)
      FormSubmissionAttempt.create(form_submission: submission)
    end

    ##
    # Marks the submission attempt as successful
    #
    # @param submission_attempt [BGS::SubmissionAttempt] The attempt to mark as succeeded
    # @return [Boolean, nil] Result of status update, or nil if attempt doesn't exist
    def mark_submission_attempt_succeeded(submission_attempt)
      submission_attempt&.succeed!
    end

    ##
    # Marks the submission attempt as failed with error details
    #
    # @param exception [Exception] The exception that caused the failure
    # @return [Boolean, nil] Result of status update, or nil if attempt doesn't exist
    def mark_submission_attempt_failed(submission_attempt, exception)
      submission_attempt&.update(error_message: exception.message)
      submission_attempt&.fail!
    end

    # Memoized BGS service
    #
    # @return [BGS::Service] BGS service object
    def bgs_service
      @bgs_service ||= ::BGS::Service.new(generate_user_struct)
    end

    # Memoized Claims API service
    #
    # @return [BEP::Claims::Service] BEP Claims API service object
    def claims_api_service
      @claims_api_service ||= ::BEP::Claims::Service.new
    end

    # Format full name
    #
    # Helper method to turn a name Hash into a string
    # @param [Hash] full_name
    # @return [string] name
    def format_full_name(full_name)
      return '' if full_name.blank?

      "#{full_name['first']} #{full_name['last']}"
    end
  end
end
