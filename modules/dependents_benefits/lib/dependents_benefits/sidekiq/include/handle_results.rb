# frozen_string_literal: true

module DependentsBenefits::Sidekiq::Include
  # methods to handle job results
  module HandleResults
    private

    # Returns a memoized instance of the claim processor
    # @return [DependentsBenefits::ClaimProcessor] Processor for handling claim operations
    def claim_processor
      @claim_processor ||= DependentsBenefits::ClaimProcessor.new(parent_claim_id)
    end

    # Determines if an error represents a permanent failure
    #
    # Override in subclasses for service-specific permanent failures
    # (e.g., INVALID_SSN, DUPLICATE_CLAIM, etc). Base implementation assumes
    # all errors are transient.
    #
    # @param error [Exception, nil] The error to check
    # @return [Boolean] true if error is permanent, false if transient
    def permanent_failure?(_error)
      false # Base: assume all errors are transient
    end

    # Handles successful job completion with coordinated status updates
    # @return [void]
    def handle_job_success
      monitor.track_info_event("Successfully submitted #{self.class} for parent_claim_id #{parent_claim_id}",
                               action: 'success', component:, parent_claim_id:)
      handle_successful_submission
    rescue => e
      monitor.track_error_event("Error handling job success #{self.class}",
                                action: 'success_failure', component:, error: e, parent_claim_id:)
    end

    # Handles successful submission
    # @return [void]
    def handle_successful_submission
      claim_processor.handle_successful_submission
    end

    # Handles job failure by determining if error is permanent or transient
    #
    # Marks the submission attempt as failed. For permanent failures, skips Sidekiq
    # retries and triggers permanent failure handling. For transient failures,
    # raises error to trigger Sidekiq retry mechanism.
    # Distinguishes permanent vs transient failures for retry logic.
    #
    # @param error [Exception] The error that caused the job to fail
    # @return [void]
    # @raise [::Sidekiq::JobRetry::Skip] for permanent failures to skip retries
    def handle_job_failure(error)
      monitor.track_error_event("Error submitting #{self.class}",
                                action: 'error', component:, error:,
                                parent_claim_id:, claim_id: parent_claim_id, proc_id:)

      if permanent_failure?(error)
        # Skip Sidekiq retries for permanent failures
        handle_permanent_failure(error)
        raise ::Sidekiq::JobRetry::Skip
      end

      # raise other errors to trigger Sidekiq retry mechanism
      raise error
    end

    # Handles job permanent failure
    #
    # @param error [Exception] The error that caused the job to fail
    # @return [void]
    def handle_permanent_failure(error)
      claim_processor.handle_permanent_failure(error)
    end
  end
end
