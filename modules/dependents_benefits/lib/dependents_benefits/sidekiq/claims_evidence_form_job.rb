# frozen_string_literal: true

require 'claims_evidence_api/uploader'
require 'dependents_benefits/pdf_stamper'
require 'dependents_benefits/service_response'
require 'dependents_benefits/sidekiq/dependent_submission_job'
require 'pdf_fill/overflow_tracker'

module DependentsBenefits::Sidekiq
  ##
  # Submission job for dependent benefits forms via Claims Evidence API
  #
  # Handles the submission of dependent benefits forms (674, 686c) to the Claims
  # Evidence API. Processes the claim PDF, validates it, and uploads to the
  # veteran's eFolder. Detects permanent VEFS errors for appropriate retry behavior.
  #
  # This is an abstract base class that requires subclasses to implement:
  # - {#submit_686c_form}
  # - {#submit_674_form}
  #
  # @abstract Subclasses must implement abstract methods
  # @see DependentSubmissionJob
  # @see ClaimsEvidenceApi::Submission
  # @see ClaimsEvidenceApi::SubmissionAttempt
  #
  class ClaimsEvidenceFormJob < DependentSubmissionJob
    # These are considered permanent failures that should not be retried
    PERMANENT_ERROR_CODES = [
      ClaimsEvidenceApi::Exceptions::VefsError::DISABLED_IDENTIFIER,
      ClaimsEvidenceApi::Exceptions::VefsError::INVALID_JWT,
      ClaimsEvidenceApi::Exceptions::VefsError::INVALID_X_EFOLDER_URI,
      ClaimsEvidenceApi::Exceptions::VefsError::UNAUTHORIZED,
      ClaimsEvidenceApi::Exceptions::VefsError::UNABLE_TO_RETRIEVE_VETERAN,
      ClaimsEvidenceApi::Exceptions::VefsError::UNABLE_TO_RETRIEVE_PERSON,
      ClaimsEvidenceApi::Exceptions::VefsError::DOES_NOT_CONFORM_TO_SCHEMA,
      ClaimsEvidenceApi::Exceptions::VefsError::INVALID_REQUEST
    ].freeze

    private

    ##
    # Submit all child claims to the Claims Evidence API
    #
    # @return [void]
    # @raise [DependentSubmissionError] if any claim submission fails
    def submit_claims_to_service
      super()

      submit_attachments

      DependentsBenefits::ServiceResponse.new(status: true)
    end

    ##
    # Submit a 686c form to the Claims Evidence API
    #
    # @param claim [SavedClaim] The 686c claim to submit
    # @return [void]
    def submit_686c_form(claim)
      submit_to_claims_evidence_api(claim)
    end

    ##
    # Submit a 674 form to the Claims Evidence API
    #
    # @param claim [SavedClaim] The 674 claim to submit
    # @return [void]
    def submit_674_form(claim)
      submit_to_claims_evidence_api(claim)
    end

    ##
    # Submit the attachments to the Claims Evidence API
    #
    # @return [void]
    def submit_attachments
      stamper = DependentsBenefits::PdfStamper.new(:dependents_benefits_received_at)
      form_id = parent_claim.claim_form_type
      uploader = claims_evidence_uploader(parent_claim)

      parent_claim.persistent_attachments.each do |pa|
        doctype = pa.document_type
        file_path = stamper.run(pa.to_pdf, timestamp: pa.created_at)
        uploader.upload_evidence(parent_claim_id, pa.id, file_path:, form_id:, doctype:)
      end
    end

    ##
    # Submit a claim to the Claims Evidence API
    #
    # @param claim [SavedClaim] The claim to submit
    # @return [void]
    def submit_to_claims_evidence_api(claim)
      stamp_set = DependentsBenefits::PdfStamper.form_stamp_set(claim.form_id)
      stamper = DependentsBenefits::PdfStamper.new(stamp_set)

      @file_path = if Flipper.enabled?(:enable_686_674_digital_pdf)
                     claim.to_dpdf
                   else
                     stamper.run(claim.to_pdf, timestamp: claim.created_at)
                   end

      claims_evidence_uploader(claim).upload_evidence(
        claim.id,
        file_path: @file_path,
        form_id: claim.form_id,
        doctype: claim.document_type
      )
    end

    # Returns a Claims Evidence API uploader instance
    #
    # @param claim [SavedClaim] The claim containing folder identifier
    # @return [ClaimsEvidenceApi::Uploader] Uploader configured with claim's folder identifier
    def claims_evidence_uploader(claim)
      ClaimsEvidenceApi::Uploader.new(claim.folder_identifier)
    end

    ##
    # Finds or creates a Claims Evidence API submission record
    #
    # Uses find_or_create_by to generate or return a memoized service-specific
    # form submission record. The record is keyed by form_id and saved_claim_id.
    #
    # @param claim [SavedClaim] The claim to find or create a submission for
    # @return [ClaimsEvidenceApi::Submission] The submission record (memoized)
    def find_or_create_form_submission(claim)
      ClaimsEvidenceApi::Submission.find_or_create_by(form_id: claim.form_id, saved_claim_id: claim.id)
    end

    ##
    # Check if a submission has already succeeded
    #
    # @param submission [ClaimsEvidenceApi::Submission] The form submission record to check
    # @return [Boolean] true if submission has an accepted attempt
    def submission_previously_succeeded?(submission)
      submission&.submission_attempts&.exists?(status: 'accepted')
    end

    ##
    # Generates a new form submission attempt record
    #
    # Each retry gets its own attempt record for debugging and tracking purposes.
    # The attempt is associated with the parent submission record.
    #
    # @param submission [ClaimsEvidenceApi::Submission] The submission to create an attempt for
    # @return [ClaimsEvidenceApi::SubmissionAttempt] The newly created attempt record (memoized)
    def create_form_submission_attempt(submission)
      ClaimsEvidenceApi::SubmissionAttempt.create(submission:)
    end

    ##
    # Marks the submission attempt as successful
    #
    # Service-specific success logic - updates the submission attempt record to
    # accepted status. Called after successful Claims Evidence API submission.
    #
    # @param submission_attempt [ClaimsEvidenceApi::SubmissionAttempt] The attempt to mark as succeeded
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
    # No-op for Claims Evidence API submissions
    #
    # ClaimsEvidenceApi::Submission records do not have a status field, so this method is a no-op.
    # This differs from other submission types (e.g., EVSS), which may require
    # status updates on the submission record itself when a failure occurs.
    #
    # @param _exception [Exception] The exception that caused the failure (unused)
    # @return [nil]
    def mark_submission_failed(_exception)
      nil
    end

    ##
    # Determines if an error represents a permanent VEFS failure
    #
    # Checks for Claims Evidence API VEFS errors and identifies specific error codes
    # that should not be retried (authentication, authorization, schema validation, etc.).
    # Permanent failures will not trigger job retries, while transient errors will.
    #
    # @param error [Exception, nil] The error to check
    # @return [Boolean] true if error represents a permanent VEFS failure, false if transient or nil
    # @see ClaimsEvidenceApi::Exceptions::VefsError
    def permanent_failure?(error)
      return false if error.nil?

      # Check for Claims Evidence API permanent failures
      if error.is_a?(ClaimsEvidenceApi::Exceptions::VefsError) || error.cause.is_a?(ClaimsEvidenceApi::Exceptions::VefsError)
        vefs_error = error.is_a?(ClaimsEvidenceApi::Exceptions::VefsError) ? error : error.cause

        return PERMANENT_ERROR_CODES.any? { |code| vefs_error.message.include?(code) }
      end

      false
    end

    ##
    # Track metrics for PDF overflow and PDF overflow by field
    #
    # @param claim [SavedClaim]
    def handle_pdf_overflow_tracking(claim)
      return unless claim.track_pdf_overflow?

      PdfFill::OverflowTracker.new(claim).track_pdf_overflow(@file_path)
    rescue
      nil
    end
  end
end
