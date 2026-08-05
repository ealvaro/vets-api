# frozen_string_literal: true

require 'dependents_benefits/helper'
require 'dependents_benefits/sidekiq/benefits_intake_job'
require 'dependents_benefits/sidekiq/bgs_form_job'
require 'dependents_benefits/sidekiq/claims_evidence_form_job'

module DependentsBenefits
  ##
  # Processes dependent benefit claims and coordinates submission jobs
  #
  # Handles the creation of child claims (686c, 674) from parent claims and
  # orchestrates the enqueueing of submission jobs to multiple services (BGS, Claims).
  # Tracks submission status and handles failures during the enqueueing process.
  #
  class ClaimProcessor
    include DependentsBenefits::Helper

    # Synchronously enqueues all (async) submission jobs for 686c and 674 claims
    #
    # Factory method that instantiates a processor and triggers submission job
    # enqueueing for a parent claim and its child claims.
    #
    # @param parent_claim_id [Integer] ID of the parent SavedClaim
    # @return [Hash] Success result with :jobs_enqueued count and :error nil
    # @raise [StandardError] If any submission job fails to enqueue
    def self.enqueue_submissions(parent_claim_id)
      new(parent_claim_id).enqueue_submissions
    end

    # Initializes a new ClaimProcessor
    #
    # @param parent_claim_id [Integer] ID of the parent SavedClaim
    def initialize(parent_claim_id)
      @parent_claim_id = parent_claim_id
    end

    # Enqueues submission jobs for all child claims
    #
    # Enqueues BGS and Claims Evidence submission jobs for the parent claim.
    # Tracks the number of jobs enqueued and handles failures by updating parent claim
    # group status.
    #
    # @return [Hash] Success result with :jobs_enqueued count and :error nil
    # @raise [StandardError] If enqueueing fails
    def enqueue_submissions
      monitor.track_info_event('Starting claim submission processing', action: 'start', component:, parent_claim_id:)

      mark_in_progress_form_pending

      enqueue_background_jobs
      # Records successful enqueueing by updating claim group status
      mark_parent_group_enqueued
      # notify user that processing has started
      notification_email.send_submitted_notification
    rescue => e
      monitor.track_error_event('Failed to enqueue submission jobs',
                                action: 'enqueue_failure', component:, parent_claim_id:, error: e.message)
      mark_parent_group_failed

      # Re-raise the original error after handling to return to user
      raise e
    end

    # Handle permanent submission failure
    #
    # Marks parent group as failed and enqueues backup job if not already completed.
    # Sends error notification if transaction fails.
    #
    # @param error [Exception] The error that caused the failure
    # @return [void]
    def handle_permanent_failure(error)
      monitor.track_error_event("Error submitting #{self.class}",
                                action: 'error.permanent', component:, error:, parent_claim_id:)
      ActiveRecord::Base.transaction do
        parent_group.with_lock do
          unless parent_group&.completed?
            mark_parent_group_failed

            DependentsBenefits::Sidekiq::BenefitsIntakeJob.perform_async(parent_claim_id)

            destroy_in_progress_form
          end
        end
      end
    rescue => e
      begin
        notification_email.send_error_notification
        mark_in_progress_form_pending
        monitor.log_silent_failure_avoided({ parent_claim_id:, error: e })
      rescue => e
        # Last resort notification fails
        monitor.log_silent_failure({ parent_claim_id:, error: e })
      end
    end

    # Handle successful submission of all child claims
    #
    # Checks if all child claims succeeded and marks parent group as succeeded.
    # Sends received notification to veteran.
    #
    # @return [void]
    def handle_successful_submission
      monitor.track_info_event('Checking if claim submissions succeeded',
                               action: 'success_check', component:, parent_claim_id:)

      ActiveRecord::Base.transaction do
        parent_group.with_lock do
          if all_claims_succeeded?
            monitor.track_info_event('All claim submissions succeeded', action: 'success', component:, parent_claim_id:)
            mark_parent_group_succeeded
            notification_email.send_received_notification
            track_successful_special_claim_types
            destroy_in_progress_form
          end
        end
      end
    rescue => e
      monitor.track_error_event("Error handling successful submission for #{self.class}",
                                action: 'success.error', component:, error: e, parent_claim_id:)
    end

    private

    attr_reader :parent_claim_id

    # Enqueues background jobs for BGS and Claims Evidence
    # @return [Integer] Number of jobs enqueued
    def enqueue_background_jobs
      jobs = if Flipper.enabled?(:enable_dependents_claims_api_job)
               {
                 DependentsBenefits::Sidekiq::ClaimsApiJob => [parent_claim_id],
                 DependentsBenefits::Sidekiq::ClaimsEvidenceFormJob => [parent_claim_id]
               }
             else
               {
                 DependentsBenefits::Sidekiq::BGSFormJob => [parent_claim_id],
                 DependentsBenefits::Sidekiq::ClaimsEvidenceFormJob => [parent_claim_id]
               }
             end

      jobs.each { |job, args| job.perform_async(*args) }

      monitor.track_info_event('Successfully enqueued all submission jobs',
                               action: 'enqueue_success',
                               component:,
                               parent_claim_id:,
                               jobs_count: jobs.length,
                               jobs_list: jobs.keys.map(&:name))
    end

    # Tracks special claim types (pension-related and no-SSN claims)
    # @return [void]
    def track_successful_special_claim_types
      track_pension_related_submissions
      track_no_ssn_claim_submissions
    end

    # Tracks pension-related claim submission for each child claim
    # @return [void]
    def track_pension_related_submissions
      return unless parent_claim.pension_related_submission?

      form_type = parent_claim&.claim_form_type
      child_claims.each do |claim|
        monitor.track_info_event('Successful pension-related claim submission',
                                 action: 'pension.submission',
                                 component:,
                                 claim_id: claim.id,
                                 form_id: claim.form_id,
                                 parent_claim_id:,
                                 form_type:,
                                 module_stats_key: DependentsBenefits::Monitor::PENSION_SUBMISSION_STATS_KEY)
      end
    end

    # Tracks no-SSN claim submission for each child claim
    # @return [void]
    def track_no_ssn_claim_submissions
      form_type = parent_claim&.claim_form_type
      child_claims.each do |claim|
        if claim.no_ssn_claim?
          monitor.track_info_event('Successful no-SSN claim submission',
                                   action: 'no_ssn_claim.submission',
                                   component:,
                                   claim_id: claim.id,
                                   form_id: claim.form_id,
                                   parent_claim_id:,
                                   form_type:,
                                   module_stats_key: DependentsBenefits::Monitor::NO_SSN_SUBMISSION_STATS_KEY)

        end
      end
    end
  end
end
