# frozen_string_literal: true

require 'bgs/job'
require 'bgs/form686c'
require 'bgs/form674'
require 'bgs/vnp_veteran'
require 'bgs/vnp_benefit_claim'
require 'bgs/benefit_claim'
require 'bgs/person_cache'
require 'dependents_benefits/sidekiq/dependent_submission_job'

module DependentsBenefits::Sidekiq
  ##
  # Submission job for dependent benefits forms via BGS
  #
  # Handles the submission of dependent benefits forms (674, 686c) to BGS (Benefits
  # Gateway Service). Normalizes claim data, validates the claim, and submits to
  # BGS using the appropriate BGS service. Detects permanent BGS errors for
  # appropriate retry behavior.
  #
  # This is an abstract base class that requires subclasses to implement:
  # - {#submit_686c_form}
  # - {#submit_674_form}
  # @abstract Subclasses must implement abstract methods
  # @see DependentSubmissionJob
  # @see BGS::Submission
  # @see BGS::SubmissionAttempt
  #
  class BGSFormJob < DependentSubmissionJob
    # 21-686C Add/Remove Dependent form_id
    ADD_REMOVE_DEPENDENT = DependentsBenefits::ADD_REMOVE_DEPENDENT.downcase
    # 21-674 School Attendance Approval form_id
    SCHOOL_ATTENDANCE_APPROVAL = DependentsBenefits::SCHOOL_ATTENDANCE_APPROVAL

    # Reasons for manual processing
    MANUAL_REASON_NOTES = {
      report_death: 'for removal of a child/dependent parent due to death.',
      add_spouse: 'to add a spouse due to civic/non-ceremonial marriage.',
      report_stepchild_not_in_household: 'for removal of a step-child that has left household.',
      report_marriage_of_child_under18: 'for removal of a married minor child.',
      report_child18_or_older_is_not_attending_school:
        'for removal of a schoolchild over 18 who has stopped attending school.',
      report674: 'along with a 674.'
    }.with_indifferent_access.freeze

    private

    ##
    # Submit all child claims to BGS
    #
    # @return [void]
    # @raise [DependentSubmissionError] if any claim submission fails
    def submit_claims_to_service
      @proc_id = generate_proc_id
      if Flipper.enabled?(:enable_combined_form_bgs_processing) &&
         child_claims.size > 1

        monitor.track_info_event('686C+674 combined claim submission started',
                                 action: 'combined.start',
                                 proc_id: @proc_id,
                                 parent_claim_id: parent_claim.id)

        benefit_claim_data = send_combined_bgs_data

        # determine correct end product code and if this requires manual processing
        proc_state = check_for_manual_claim(benefit_claim_data[:benefit_claim_id])

        bgs_service.update_proc(@proc_id, proc_state:)
        monitor.track_info_event("686C+674 combined claim submitted to RBPS with proc_state of #{proc_state}",
                                 action: 'combined.success', proc_id: @proc_id, automatic: proc_state == 'Ready',
                                 parent_claim_id: parent_claim.id)

        DependentsBenefits::ServiceResponse.new(status: true)
      else
        super()
      end
    end

    ##
    # Create veteran, send claim data to BGS
    #
    # @return [BGS::VnpVeteran data]
    def send_combined_bgs_data
      ep_code = parent_claim.submittable_686? ? '130DPNEBNADJ' : '130SCHATTEBN'
      ep_name = if parent_claim.submittable_686?
                  '130 - Automated Dependency 686c'
                else
                  '130 - Automated School Attendance 674'
                end

      # create veteran object in VNP tables
      user = generate_user_struct
      veteran = ::BGS::VnpVeteran.new(proc_id:, payload: normalized_form_data, user:, claim_type: ep_code).create

      person_cache = ::BGS::PersonCache.new(user)
      # send 686, 674 data. We want to process the 686 data, if any, first
      child_claims.sort_by { |c| c.form_id == DependentsBenefits::ADD_REMOVE_DEPENDENT ? 0 : 1 }.each do |claim|
        service_response = send_combined_claim_part(claim, veteran, person_cache)
        raise DependentSubmissionError, service_response&.error unless service_response&.success?
      end

      # create benefit claim with correct end_product_code
      create_combined_benefit_claim(
        veteran:, user:, ep_name:, ep_code:
      )
    end

    ##
    # Submit an individual child claims to BGS
    #
    # @return [void]
    def send_combined_claim_part(claim, veteran, person_cache)
      submission = find_or_create_form_submission(claim)
      submission_attempt = create_form_submission_attempt(submission)
      claim.user_data # populates and retrieves if not already present on claim
      if claim.form_id == DependentsBenefits::ADD_REMOVE_DEPENDENT
        submit_686c_form(claim, { veteran:, skip_claim_create: true, person_cache: })
      elsif claim.form_id == DependentsBenefits::SCHOOL_ATTENDANCE_APPROVAL
        submit_674_form(claim, { veteran:, skip_claim_create: true, person_cache: })
      end
      mark_submission_attempt_succeeded(submission_attempt)
      DependentsBenefits::ServiceResponse.new(status: true)
    rescue => e
      monitor.track_error_event("Submission attempt failure in #{self.class}",
                                action: 'claim.error', component:, error: e.message,
                                parent_claim_id:, saved_claim_id: claim.id, proc_id:)
      mark_submission_attempt_failed(submission_attempt, e)
      mark_in_progress_form_pending
      DependentsBenefits::ServiceResponse.new(status: false, error: e.message)
    end

    ##
    # Create combined benefit claim
    #
    # @param veteran [VnpVeteran] The veteran object
    # @param user [Hash] The user object
    # @return [Hash] benefit claim data
    def create_combined_benefit_claim(veteran:, user:, ep_name:, ep_code:)
      vnp_benefit_claim = ::BGS::VnpBenefitClaim.new(proc_id:, veteran:, user:)
      vnp_benefit_claim_record = vnp_benefit_claim.create

      benefit_claim_record = ::BGS::BenefitClaim.new(
        args: {
          vnp_benefit_claim: vnp_benefit_claim_record,
          veteran:,
          user:,
          proc_id:,
          end_product_name: ep_name,
          end_product_code: ep_code
        }
      ).create
      vnp_benefit_claim.update(benefit_claim_record, vnp_benefit_claim_record)
      benefit_claim_record
    end

    ##
    # Determine if a 686+674 claim needs manual processing
    #
    # @param form_data[Hash] form data
    # @return [String] desired proc_state
    def check_for_manual_claim(benefit_claim_id)
      manual_reason = manual_processing_reason

      if manual_reason.present?
        # manual claims warrant a note to tell RBPS why it requires manual processing
        note_text = 'Claim set to manual by VA.gov: This application needs manual review ' \
                    "because a 686 was submitted #{MANUAL_REASON_NOTES[manual_reason]}"
        bgs_service.create_note(benefit_claim_id, note_text)
        'MANUAL_VAGOV'
      else
        'Ready'
      end
    end

    ##
    # Loop through possible manual processing situations
    #
    # @return [String | nil] reason for manual processing
    def manual_processing_reason
      selectable_options = normalized_form_data['view:selectable686_options']
      dependents_app = normalized_form_data['dependents_application']

      selectable_options.each do |option, is_selected|
        return option if ::BGS::Form686c::REMOVE_CHILD_OPTIONS.include?(option) && is_selected
      end

      # if the user is adding a spouse and the marriage type is anything other than CEREMONIAL, set the status to manual
      marriage_type = dependents_app.dig('current_marriage_information', 'type_of_marriage')
      return 'add_spouse' if selectable_options['add_spouse'] && ::BGS::Form686c::MARRIAGE_TYPES.include?(marriage_type)

      # search through the array of "deaths" and check if the dependent_type = "CHILD" or "DEPENDENT_PARENT"
      death_types = (dependents_app['deaths'] || []).map { |e| e['dependent_type'] }
      'report_death' if selectable_options['report_death'] && death_types.intersect?(::BGS::Form686c::RELATIONSHIPS)
    end

    ##
    # Submit a 686c form to BGS
    #
    # @param claim [SavedClaim] The 686c claim to submit
    # @return [void]
    def submit_686c_form(claim, opts = {})
      claim_data = ::BGS::Job.new.normalize_names_and_addresses!(claim.parsed_form)

      ::BGS::Form686c.new(generate_user_struct, claim, { proc_id: @proc_id }.merge(opts)).submit(claim_data)
    end

    ##
    # Submit a 674 form to BGS
    #
    # @param claim [SavedClaim] The 674 claim to submit
    # @return [void]
    def submit_674_form(claim, opts = {})
      claim_data = ::BGS::Job.new.normalize_names_and_addresses!(claim.parsed_form)

      # If a 674 is the only claim we are submitting, we need
      # for the BGS form class to also update the proc_state
      # to 'Ready' once everything else is set.
      is_only674 = false
      if claim.is_a?(::DependentsBenefits::SchoolAttendanceApproval)
        parent_claim = SavedClaim.find_by(id: claim.parent_claim_id)
        is_only674 = parent_claim && !parent_claim&.submittable_686?
      end

      ::BGS::Form674.new(generate_user_struct, claim,
                         { proc_id: @proc_id, update_proc_state_on_complete: is_only674 }
                         .merge(opts)).submit(claim_data)
    end

    ##
    # Normalize form data
    #
    # @return [Hash]
    def normalized_form_data
      @normalized_form_data ||= ::BGS::Job.new.normalize_names_and_addresses!(parent_claim.parsed_form)
    end

    ##
    # Generate a BGS proc ID for grouping related submissions
    #
    # @return [String] The generated proc ID
    # @raise [DependentsBenefits::DependentSubmissionError] if proc ID generation fails
    def generate_proc_id
      # vnp_proc is BGS's way of grouping related form submissions together
      vnp_response = bgs_service.create_proc(proc_state: 'Started')
      raise 'BGS proc ID generation failed: No proc ID returned' if vnp_response.nil?

      @proc_id = vnp_response[:vnp_proc_id]

      bgs_service.create_proc_form(@proc_id, ADD_REMOVE_DEPENDENT) if parent_claim.submittable_686?
      bgs_service.create_proc_form(@proc_id, SCHOOL_ATTENDANCE_APPROVAL) if parent_claim.submittable_674?

      @proc_id
    rescue => e
      monitor.track_error_event('Error generating proc ID',
                                action: 'proc_id_failure', component:, error: e, parent_claim_id: parent_claim.id)
      raise DependentsBenefits::Sidekiq::DependentSubmissionError, e
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
    end

    ##
    # Finds or creates a BGS form submission record
    #
    # Uses find_or_create_by to generate or return a memoized service-specific
    # form submission record. The record is keyed by form_id and saved_claim_id.
    #
    # @param claim [SavedClaim] The claim to find or create a submission for
    # @return [BGS::Submission] The submission record (memoized)
    def find_or_create_form_submission(claim)
      ::BGS::Submission.find_or_create_by(form_id: claim.form_id, saved_claim_id: claim.id)
    end

    ##
    # Check if a submission has already succeeded
    #
    # @param submission [BGS::Submission] The form submission record to check
    # @return [Boolean] true if submission has a non-failure attempt
    def submission_previously_succeeded?(submission)
      submission&.non_failure_attempt.present?
    end

    ##
    # Generates a new form submission attempt record
    #
    # Each retry gets its own attempt record for debugging and tracking purposes.
    # The attempt is associated with the parent submission record.
    #
    # @param submission [BGS::Submission] The submission to create an attempt for
    # @return [BGS::SubmissionAttempt] The newly created attempt record (memoized)
    def create_form_submission_attempt(submission)
      ::BGS::SubmissionAttempt.create(submission:)
    end

    ##
    # Marks the submission attempt as successful
    #
    # Service-specific success logic - updates the submission attempt record to
    # success status. Called after successful BGS submission.
    #
    # @param submission_attempt [BGS::SubmissionAttempt] The attempt to mark as succeeded
    # @return [Boolean, nil] Result of status update, or nil if attempt doesn't exist
    def mark_submission_attempt_succeeded(submission_attempt)
      submission_attempt&.success!
    end

    ##
    # Marks the submission attempt as failed with error details
    #
    # Service-specific failure logic - updates the submission attempt record with
    # failure status and stores the exception details for debugging.
    #
    # @param exception [Exception] The exception that caused the failure
    # @return [Boolean, nil] Result of status update, or nil if attempt doesn't exist
    def mark_submission_attempt_failed(submission_attempt, exception)
      submission_attempt&.fail!(error: exception)
    end

    ##
    # No-op for BGS submissions
    #
    # BGS::Submission records do not have a status field, so this method is a no-op.
    # This differs from other submission types (e.g., EVSS), which may require
    # status updates on the submission record itself when a failure occurs.
    #
    # @param _exception [Exception] The exception that caused the failure (unused)
    # @return [nil]
    def mark_submission_failed(_exception) = nil

    ##
    # Determines if an error represents a permanent BGS failure
    #
    # Checks if the error message or its cause matches any of the BGS filtered errors
    # that should not be retried (e.g., invalid SSN, duplicate claim, invalid data).
    # Permanent failures will not trigger job retries, while transient errors will.
    #
    # @param error [Exception, nil] The error to check
    # @return [Boolean] true if error matches BGS permanent failure patterns, false if transient or nil
    # @see BGS::Job::FILTERED_ERRORS
    def permanent_failure?(error)
      return false if error.nil?

      ::BGS::Job::FILTERED_ERRORS.any? { |filtered| error.message.include?(filtered) || error.cause&.message&.include?(filtered) }
    end

    ##
    # Service for communicating with BGS
    #
    # @return [BGS::Service] the service object
    def bgs_service
      @bgs_service ||= ::BGS::Service.new(generate_user_struct)
    end
  end
end
