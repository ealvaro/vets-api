# frozen_string_literal: true

require 'lighthouse/benefits_intake/metadata'
require 'lighthouse/benefits_intake/service'
require 'dependents_benefits/pdf_stamper'
require 'dependents_benefits/sidekiq/dependent_submission_job'

module DependentsBenefits::Sidekiq
  ##
  # Submission job that uploads claims to Lighthouse Benefits Intake
  #
  # Used as a fallback when primary BGS submission fails. Submits the entire
  # claim package (main form and attachments) to Lighthouse Benefits Intake API.
  # Unlike primary submissions, does not fail the parent group if this fails,
  # and marks parent as PROCESSING rather than SUCCESS to indicate VBMS pending.
  #
  class BenefitsIntakeJob < DependentSubmissionJob
    private

    # Submit a claim to Lighthouse Benefits Intake as backup
    # @return [ServiceResponse]
    def submit_claims_to_service
      @form_path = generate_claim_pdfs.shift # use the first claim as the main form
      @attachment_paths = generate_attachment_pdfs
      @metadata = generate_metadata

      intake_service.request_upload # upload must be performed within 15 minutes of this request
      find_or_create_form_submission(parent_claim)
      create_form_submission_attempt(submission)

      payload = {
        upload_url: intake_service.location,
        document: @form_path,
        metadata: @metadata.to_json,
        attachments: @pdfs + @attachment_paths
      }

      response = intake_service.perform_upload(**payload)
      raise response.to_s unless response.success?

      DependentsBenefits::ServiceResponse.new(status: true, data: response.body)
    rescue => e
      DependentsBenefits::ServiceResponse.new(status: false, error: e)
    ensure
      cleanup_file_paths
    end

    # memoized instance of BenefitsIntake::Service
    def intake_service
      @intake_service ||= ::BenefitsIntake::Service.new
    end

    # Returns the Lighthouse Benefits Intake UUID for this submission
    #
    # @return [String, nil] The benefits intake UUID, or nil if not yet initialized
    def uuid
      intake_service.uuid
    end

    # Generate the child form pdfs
    #
    # @return [Array<String>] path to processed PDF document
    def generate_claim_pdfs
      @pdfs = []
      child_claims.each do |claim|
        claim.add_veteran_info(user_data)
        stamp_set = DependentsBenefits::PdfStamper.form_stamp_set(claim.form_id)
        pdf = if Flipper.enabled?(:enable_686_674_digital_pdf)
                process_pdf(claim.to_pdf, []) # stamping handled by the digital pdf service
              else
                process_pdf(claim.to_pdf, stamp_set)
              end

        # if there is a 686C claim, that should be the main claim pdf - @form_path
        claim.form_id == DependentsBenefits::ADD_REMOVE_DEPENDENT ? @pdfs.prepend(pdf) : @pdfs.append(pdf)
      end

      @pdfs
    end

    # Generate the form attachment pdfs
    #
    # @return [Array<String>] path to processed PDF document
    def generate_attachment_pdfs
      parent_claim.persistent_attachments.map { |pa| process_pdf(pa.to_pdf, :dependents_benefits_received_at) }
    end

    # Processes and stamps a PDF with submission information
    #
    # Applies multiple stamps to the PDF including VA.GOV branding, FDC review notice,
    # and optional form-specific submission date stamp
    #
    # @param pdf_path [String] Path to the PDF file to process
    # @param stamp_set [String|Symbol] the stamps to apply
    # @param timestamp [Time, nil] Optional timestamp for the submission date stamp
    #
    # @return [String] Path to the final stamped PDF file
    def process_pdf(pdf_path, stamp_set, timestamp = nil)
      timestamp ||= parent_claim.created_at
      document = DependentsBenefits::PdfStamper.new(stamp_set).run(pdf_path, timestamp:)

      intake_service.valid_document?(document:)
    end

    # Generate form metadata to send in upload to Benefits Intake API
    #
    # @see SavedClaim.parsed_form
    # @see BenefitsIntake::Metadata#generate
    #
    # @return [Hash] generated metadata for upload
    def generate_metadata
      form = parent_claim.parsed_form
      address = form.dig('dependents_application', 'veteran_contact_information', 'veteran_address') || {}
      veteran_information = user_data['veteran_information']

      # also validates/manipulates the metadata
      ::BenefitsIntake::Metadata.generate(
        veteran_information['full_name']['first'],
        veteran_information['full_name']['last'],
        veteran_information['va_file_number'] || veteran_information['ssn'],
        address['postal_code'], # will default to 00000 if not valid/present
        self.class.to_s, # upload source
        parent_claim.form_id,
        parent_claim.business_line
      )
    end

    # Cleans up temporary PDF files after submission
    #
    # Deletes the main form PDF and all attachment PDFs that were generated
    # for the submission
    #
    # @return [void]
    def cleanup_file_paths
      Common::FileHelpers.delete_file_if_exists(@form_path)
      @pdfs&.each { |pdf| Common::FileHelpers.delete_file_if_exists(pdf) }
      @attachment_paths&.each { |pa| Common::FileHelpers.delete_file_if_exists(pa) }
    end

    #############
    # OVERRIDES
    #############

    # @see DependentsBenefits::Sidekiq::Include::HandleResults#handle_job_failure
    def handle_job_failure(error)
      mark_submission_attempt_failed(@submission_attempt, error)
      super(error)
    end

    # Handles permanent failure for backup job
    #
    # Simplified failure handling compared to primary jobs - only sends failure
    # notification and logs the error. Does not update parent group status since
    # backup job failures should not prevent subsequent retry attempts.
    #
    # @param error [Exception] The error that caused the permanent failure
    # @return [void]
    def handle_permanent_failure(error)
      mark_parent_group_failed
      super(error)

      notification_email.send_error_notification
      monitor.log_silent_failure_avoided({ parent_claim_id:, error: })
    rescue => e
      # Last resort if notification fails
      monitor.log_silent_failure({ parent_claim_id:, error: e })
    end

    # Handles successful backup submission
    #
    # Marks submission as succeeded and updates parent group to PROCESSING status
    # (not SUCCESS) to indicate the claim has been accepted by Lighthouse but hasn't
    # reached VBMS yet. Sends in-progress notification to veteran. Does not check
    # sibling status since backup jobs override previous failures.
    # Atomic updates prevent partial state corruption.
    #
    # @return [void]
    def handle_job_success
      mark_parent_group_processing
      super()
    rescue => e
      monitor.track_error_event('Error handling job success',
                                action: 'success_failure', component:, error: e, parent_claim_id:)
    end

    # No-op for Lighthouse submissions
    def handle_successful_submission
      nil
    end

    # Finds or creates a Lighthouse form submission record
    #
    # Creates a Lighthouse::Submission record if one doesn't exist for this claim,
    # or returns the existing one. Sets form_id and reference_data on creation.
    #
    # @return [Lighthouse::Submission] The submission record
    def find_or_create_form_submission(claim)
      @submission = Lighthouse::Submission.find_or_create_by!(saved_claim_id: claim.id) do |submission|
        submission.assign_attributes({ form_id: claim.form_id, reference_data: claim.to_json })
      end
    end

    # Creates a new Lighthouse form submission attempt record
    #
    # Each retry gets its own attempt record for debugging and tracking.
    #
    # @return [Lighthouse::SubmissionAttempt] The newly created attempt record
    def create_form_submission_attempt(submission)
      @submission_attempt = Lighthouse::SubmissionAttempt.create(submission:, benefits_intake_uuid: uuid)
    end

    # Marks the submission attempt as failed
    #
    # Service-specific failure logic - updates submission attempt record to failed status.
    #
    # @param _exception [Exception] The exception that caused the failure (unused)
    # @return [Boolean, nil] Result of status update, or nil if attempt doesn't exist
    def mark_submission_attempt_failed(submission_attempt, _exception)
      submission_attempt&.fail!
    end

    # No-op for Lighthouse submissions
    #
    # Lighthouse submission records don't have a failed status, so this is a no-op.
    #
    # @param _exception [Exception] The exception that caused the failure (unused)
    # @return [nil]
    def mark_submission_failed(_exception)
      nil
    end

    # Always returns false for backup jobs
    #
    # Backup jobs don't check parent group status - they always attempt submission
    # regardless of previous failures, since they're the fallback mechanism.
    #
    # @see DependentsBenefits::Helper::Models#parent_group_failed?
    #
    # @return [Boolean] Always false
    def parent_group_failed?
      false
    end
  end
end
