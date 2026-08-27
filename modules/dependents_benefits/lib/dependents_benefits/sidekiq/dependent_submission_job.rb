# frozen_string_literal: true

require 'sidekiq/job_retry'

require 'dependents_benefits/helper'
require 'dependents_benefits/sidekiq/include/abstract_methods'
require 'dependents_benefits/sidekiq/include/handle_results'

module DependentsBenefits::Sidekiq
  # Custom error class for dependent submission failures
  class DependentSubmissionError < StandardError; end

  ##
  # Abstract base class for coordinated submission of related 686c and 674 claims
  #
  # COORDINATION PATTERN:
  # - Parent claim spawns multiple child claims (686c, 674s) with shared proc_id
  # - Each child gets separate job that checks sibling status before processing
  # - Uses pessimistic locking to prevent race conditions between siblings
  # - Early exits if any sibling has already failed the claim group
  class DependentSubmissionJob
    include ::Sidekiq::Job
    include DependentsBenefits::Helper
    include DependentsBenefits::Sidekiq::Include::AbstractMethods
    include DependentsBenefits::Sidekiq::Include::HandleResults

    # dead: false ensures critical dependent claims never go to dead queue
    # https://github.com/sidekiq/sidekiq/wiki/Advanced-Options#jobs
    sidekiq_options retry: 16, dead: false

    # Callback runs outside job context - must recreate instance state
    sidekiq_retries_exhausted do |msg, exception|
      monitor = DependentsBenefits::Monitor.new
      parent_claim_id, proc_id = msg['args']

      # Use the class of the inheriting job that exhausted, not the base class
      job_class_name = msg['class']
      monitor.track_info_event("Retries exhausted for #{job_class_name} parent_claim_id #{parent_claim_id}",
                               action: 'exhaustion', component: job_class_name, parent_claim_id:)

      if job_class_name.blank?
        # If we don't have a job class name, the error is irrecoverable
        monitor.log_silent_failure({ parent_claim_id:, error: exception })
      else
        job_instance = job_class_name.constantize.new
        job_instance.parent_claim_id = parent_claim_id
        job_instance.proc_id = proc_id
        job_instance.send(:handle_permanent_failure, exception)
      end
    end

    attr_accessor :parent_claim_id, :proc_id
    attr_writer :user_data

    # Main job execution method for submitting dependent claims
    #
    # Coordinates the submission of a single claim (686c or 674) to the appropriate
    # service. Implements early exit if parent group has already failed. Creates
    # form submission records and handles success/failure outcomes.
    #
    # @param parent_claim_id [Integer] ID of the parent SavedClaim to submit
    # @param proc_id [String, nil] Optional processing ID for tracking related submissions
    # @return [void]
    # @raise [DependentSubmissionError] if submission fails and should be retried
    def perform(parent_claim_id, proc_id = nil)
      @parent_claim_id = parent_claim_id
      @proc_id = proc_id
      @user_data = parent_claim.user_data # retrieve and populate 'veteran_information'

      monitor.track_info_event("Starting #{self.class} for parent_claim_id #{parent_claim_id}",
                               action: 'start', component:, parent_claim_id:, proc_id:)

      # Early exit optimization - prevents unnecessary service calls
      return if parent_group_failed?

      @service_response = submit_claims_to_service

      raise DependentSubmissionError, @service_response&.error unless @service_response&.success?

      handle_job_success
    rescue => e
      handle_job_failure(e)
    end

    # Returns truncated common name with max 39 characters for BGS external_key used for the BGS submission.
    #
    # @return [String] the formatted common name
    def formatted_common_name(common_name)
      return common_name unless Flipper.enabled?(:bgs_truncate_external_key)

      common_name&.first(BGS::Constants::EXTERNAL_KEY_MAX_LENGTH)
    end

    private

    # memoize the job user_data
    def user_data
      @user_data ||= parent_claim.user_data
    end

    # Submit all child claims to the service
    #
    # @return [DependentsBenefits::ServiceResponse] Response indicating success
    # @raise [DependentSubmissionError] if any claim submission fails
    def submit_claims_to_service
      child_claims.each do |claim|
        service_response = submit_claim_to_service(claim)
        raise DependentSubmissionError, service_response&.error unless service_response&.success?
      end

      DependentsBenefits::ServiceResponse.new(status: true)
    end

    # Submit a single claim to the service
    # @param claim [SavedClaim] The claim to submit
    # @return [DependentsBenefits::ServiceResponse] Response indicating success or failure
    # rubocop:disable Metrics/MethodLength
    def submit_claim_to_service(claim)
      submission = find_or_create_form_submission(claim)
      return DependentsBenefits::ServiceResponse.new(status: true) if submission_previously_succeeded?(submission)

      submission_attempt = create_form_submission_attempt(submission)
      claim.user_data # populates and retrieves if not already present on claim
      if claim.form_id == DependentsBenefits::ADD_REMOVE_DEPENDENT
        raise DependentsBenefits::Invalid686cClaim unless claim.valid?(:run_686_form_jobs)

        submit_686c_form(claim)
      elsif claim.form_id == DependentsBenefits::SCHOOL_ATTENDANCE_APPROVAL
        raise DependentsBenefits::Invalid674Claim unless claim.valid?(:run_686_form_jobs)

        submit_674_form(claim)
      end
      mark_submission_attempt_succeeded(submission_attempt)
      handle_pdf_overflow_tracking(claim)
      DependentsBenefits::ServiceResponse.new(status: true)
    rescue => e
      monitor.track_error_event("Submission attempt failure in #{self.class}",
                                action: 'claim.error', component:, error: e.message,
                                parent_claim_id:, saved_claim_id: claim.id, proc_id:)
      mark_submission_attempt_failed(submission_attempt, e)
      mark_in_progress_form_pending
      DependentsBenefits::ServiceResponse.new(status: false, error: e.message)
    end
    # rubocop:enable Metrics/MethodLength

    ##
    # Track metrics for PDF overflow and PDF overflow by field
    #
    # @see ClaimsEvidenceFormJob#handle_pdf_overflow_tracking
    #
    # @param claim [SavedClaim]
    def handle_pdf_overflow_tracking(_claim); end
  end
end
