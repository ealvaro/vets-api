# frozen_string_literal: true

module DependentsBenefits::Sidekiq::Include
  # abstarct methods for sidekiq jobs
  module AbstractMethods
    private

    # Submit claims to the appropriate service
    # @abstract Subclasses must implement this method
    # @return [void]
    def submit_claims_to_service
      raise NotImplementedError, 'Subclasses must implement submit_claims_to_service method'
    end

    # Submit a 686c form to the service
    # @abstract Subclasses must implement this method
    # @param claim [SavedClaim] The 686c claim to submit
    # @return [void]
    def submit_686c_form(claim)
      raise NotImplementedError, 'Subclasses must implement submit_686c_form method'
    end

    # Submit a 674 form to the service
    # @abstract Subclasses must implement this method
    # @param claim [SavedClaim] The 674 claim to submit
    # @return [void]
    def submit_674_form(claim)
      raise NotImplementedError, 'Subclasses must implement submit_674_form method'
    end

    # Check if a submission has already succeeded
    # @abstract Subclasses must implement this method
    # @param submission [FormSubmission] The form submission record to check
    # @return [Boolean] true if submission previously succeeded
    def submission_previously_succeeded?(submission)
      raise NotImplementedError, 'Subclasses must implement submission_previously_succeeded?'
    end

    # Use .find_or_create to generate/return memoized service-specific form submission record
    # @return [LighthouseFormSubmission, BGSFormSubmission] instance
    def find_or_create_form_submission(claim)
      raise NotImplementedError, 'Subclasses must implement find_or_create_form_submission'
    end

    # Generate a new form submission attempt record
    # Each retry gets its own attempt record for debugging
    # @return [LighthouseFormSubmissionAttempt, BGSFormSubmissionAttempt] instance
    def create_form_submission_attempt(submission)
      raise NotImplementedError, 'Subclasses must implement create_form_submission_attempt'
    end

    # Mark a submission attempt as succeeded
    # @abstract Subclasses must implement this method
    # @param submission_attempt [FormSubmissionAttempt] The attempt to mark as succeeded
    # @return [void]
    def mark_submission_attempt_succeeded(submission_attempt)
      raise NotImplementedError, 'Subclasses must implement mark_submission_attempt_succeeded'
    end

    # Service-specific failure logic
    # Update submission attempt record only with failure and error details
    def mark_submission_attempt_failed(submission_attempt, exception)
      raise NotImplementedError, 'Subclasses must implement mark_submission_attempt_failed'
    end

    # Service-specific failure logic for permanent failures
    # Update form submission record to failed
    def mark_submission_failed(exception)
      raise NotImplementedError, 'Subclasses must implement mark_submission_failed'
    end

    # Returns the memoized form submission record
    #
    # @return [LighthouseFormSubmission, BGSFormSubmission] The submission record
    def submission
      @submission ||= find_or_create_form_submission
    end

    # Returns the memoized form submission attempt record
    #
    # @return [LighthouseFormSubmissionAttempt, BGSFormSubmissionAttempt] The attempt record
    def submission_attempt
      @submission_attempt ||= create_form_submission_attempt
    end
  end
end
