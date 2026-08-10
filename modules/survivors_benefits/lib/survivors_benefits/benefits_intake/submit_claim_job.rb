# frozen_string_literal: true

require 'ibm/service'
require 'lighthouse/benefits_intake/service'
require 'lighthouse/benefits_intake/metadata'
require 'survivors_benefits/notification_email'
require 'survivors_benefits/monitor'
require 'survivors_benefits/benefits_intake/update_form_submission_attempt_job'
require 'pdf_utilities/datestamp_pdf'

module SurvivorsBenefits
  module BenefitsIntake
    # Sidekiq job to send pension pdf to Lighthouse:BenefitsIntake API
    # @see https://developer.va.gov/explore/api/benefits-intake/docs
    class SubmitClaimJob
      include Sidekiq::Job

      # Error if "Unable to find SurvivorsBenefits::SavedClaim"
      class SurvivorsBenefitsBenefitIntakeError < StandardError; end

      # retry for  2d 1h 47m 12s
      # https://github.com/sidekiq/sidekiq/wiki/Error-Handling
      sidekiq_options retry: 16, queue: 'low'
      sidekiq_retries_exhausted do |msg|
        ia_monitor = SurvivorsBenefits::Monitor.new
        begin
          claim = SurvivorsBenefits::SavedClaim.find(msg['args'].first)
        rescue
          claim = nil
        end
        ia_monitor.track_submission_exhaustion(msg, claim)
      end

      ##
      # Process pdfs and upload to Benefits Intake API
      #
      # @param saved_claim_id [Integer] the claim id
      # @param user_account_uuid [UUID] the user submitting the form
      #
      # @return [UUID] benefits intake upload uuid
      #
      def perform(saved_claim_id, user_account_uuid = nil)
        return unless Flipper.enabled?(:survivors_benefits_form_enabled)

        init(saved_claim_id, user_account_uuid)
        # benefits_intake_uuid comes from here
        @intake_service ||= reset_intake_service

        # generate and validate claim pdf documents.
        # to_stamped_pdf suppresses the shared machinery's built-in bottom-left footer and stamps the
        # submission date/timestamp/authentication watermark on the bottom-right of every page — the
        # same treatment the confirmation-page download copy gets in ClaimsController#create.
        @stamped_pdf_path = @claim.to_stamped_pdf(@claim.id)
        @form_path = process_document(@stamped_pdf_path)
        @attachment_paths = @claim.persistent_attachments.map { |pa| process_document(pa.to_pdf) }
        @metadata = generate_metadata
        @ibm_payload = @claim.to_ibm if Flipper.enabled?(:survivors_benefits_structured_data_transmission)

        # upload must be performed within 15 minutes of this request
        upload_document

        send_submitted_email
        monitor.track_submission_success(@claim, @intake_service, @user_account_uuid)

        @intake_service.uuid
      rescue => e
        monitor.track_submission_retry(@claim, @intake_service, @user_account_uuid, e)
        @lighthouse_submission_attempt&.fail!
        raise e
      ensure
        cleanup_file_paths
      end

      private

      # Instantiate instance variables for _this_ job
      def init(saved_claim_id, user_account_uuid)
        @user_account_uuid = user_account_uuid
        @user_account = UserAccount.find(@user_account_uuid) if @user_account_uuid.present?
        # UserAccount.find will raise an error if unable to find the user_account record

        @claim = SurvivorsBenefits::SavedClaim.find(saved_claim_id)
        unless @claim
          raise SurvivorsBenefitsBenefitIntakeError,
                "Unable to find SurvivorsBenefits::SavedClaim #{saved_claim_id}"
        end
      end

      # Create a monitor to be used for _this_ job
      # @see SurvivorsBenefits::Monitor
      def monitor
        @monitor ||= SurvivorsBenefits::Monitor.new
      end

      # Create a temp stamped PDF and validate the PDF satisfies Benefits Intake specification
      #
      # @param [String] file_path
      #
      # @return [String] path to stamped PDF
      def process_document(file_path)
        document = PDFUtilities::DatestampPdf.new(file_path).run(text: 'VA.GOV', x: 5, y: 5)
        document = PDFUtilities::DatestampPdf.new(document).run(
          text: 'FDC Reviewed - VA.gov Submission',
          x: 429,
          y: 770,
          text_only: true
        )

        @intake_service.valid_document?(document:)
      end

      # Generate form metadata to send in upload to Benefits Intake API
      #
      # @see https://developer.va.gov/explore/api/benefits-intake/docs
      # @see SavedClaim.parsed_form
      # @see BenefitsIntake::Metadata
      #
      # @return [Hash]
      def generate_metadata
        form = @claim.parsed_form
        address = form['claimantAddress'].presence || form['veteranAddress'].presence || {}

        # also validates/maniuplates the metadata
        # BenefitsIntake::Metadata.generate expects:
        #   (first_name, last_name, file_number, zip_code, source, doc_type, business_line = nil)
        first = form.dig('veteranFullName', 'first')
        last = form.dig('veteranFullName', 'last')
        file_number = form['vaFileNumber'] || form['veteranSocialSecurityNumber']
        zip_code = address['postalCode']
        source = 'va_gov_benefits_intake_huntridge_labs'
        doc_type = "StructuredData:#{@claim.form_id}"
        business_line = @claim.business_line

        ::BenefitsIntake::Metadata.generate(first, last, file_number, zip_code, source, doc_type, business_line)
      end

      # Upload generated pdf to Benefits Intake API
      def upload_document
        @intake_service.request_upload
        monitor.track_submission_begun(@claim, @intake_service, @user_account_uuid)
        lighthouse_submission_polling

        payload = {
          upload_url: @intake_service.location,
          document: @form_path,
          metadata: @metadata.to_json,
          attachments: @attachment_paths
        }
        tracked_payload = payload.merge(
          ibm_payload_present: @ibm_payload.present?,
          ibm_payload_field_count: @ibm_payload&.keys&.count
        )

        monitor.track_submission_attempted(@claim, @intake_service, @user_account_uuid, tracked_payload)

        response = @intake_service.perform_upload(**payload)
        update_form_submission_attempt
        govcio_upload if response.success?

        raise SurvivorsBenefitsBenefitIntakeError, response.to_s unless response.success?
      end

      # MyVA relies on SubmissionAttempt records to find submitted forms and create Submission
      # in Progress cards on the MyVA page
      #
      # This is post-upload bookkeeping ONLY and must never raise out of the job. By the time it
      # runs the document has already been handed to Lighthouse (see #upload_document), so a
      # raise here would propagate to #perform, be re-raised, and cause Sidekiq to retry the whole
      # job -- which re-runs perform_upload and RE-UPLOADS the document under a new intake uuid,
      # i.e. a duplicate submission. On failure the write is retried asynchronously by
      # UpdateFormSubmissionAttemptJob (which re-derives the current intake uuid), so the
      # bookkeeping is eventually consistent without sitting on the upload's critical path.
      # Mirrors the non-fatal pattern already used by #govcio_upload and #send_submitted_email.
      #
      # @see UpdateFormSubmissionAttemptJob.update_form_submission_attempt (shared, idempotent)
      #
      # @return [FormSubmissionAttempt, nil] the attempt on success; nil when the write failed and
      #   was swallowed (bookkeeping is then deferred to UpdateFormSubmissionAttemptJob)
      def update_form_submission_attempt
        UpdateFormSubmissionAttemptJob.update_form_submission_attempt(@claim, @intake_service.uuid)
      rescue => e
        # Never fail the job for MyVA bookkeeping - a successful Lighthouse upload must be terminal.
        Rails.logger.error(
          'SurvivorsBenefits::BenefitsIntake::SubmitClaimJob update_form_submission_attempt failed',
          claim_id: @claim&.id, benefits_intake_uuid: @intake_service&.uuid, error: e.message
        )
        begin
          UpdateFormSubmissionAttemptJob.perform_async(@claim.id) if @claim
        rescue => enqueue_error
          # Even a failed enqueue must not fail the job; the error log above still has the
          # claim_id + uuid needed for a manual backfill.
          Rails.logger.error(
            'SurvivorsBenefits::BenefitsIntake::SubmitClaimJob failed to enqueue UpdateFormSubmissionAttemptJob',
            claim_id: @claim&.id, error: enqueue_error.message
          )
        end
        nil
      end

      # Create a new instance of the Benefits Intake service for this job
      #
      # @return BenefitsIntake::Service
      def reset_intake_service
        @intake_service = ::BenefitsIntake::Service.new
      end

      def govcio_upload
        return unless Flipper.enabled?(:survivors_benefits_structured_data_transmission)

        ibm_service = Ibm::Service.new
        ibm_service.upload_form(form: @ibm_payload.to_json, guid: @intake_service.uuid)
      rescue => e
        Rails.logger.error("IBM structured data transmission failed: #{e.message}")
      end

      # Insert submission polling entries
      def lighthouse_submission_polling
        lighthouse_submission = {
          form_id: @claim.form_id,
          reference_data: @claim.to_json,
          saved_claim: @claim
        }

        Lighthouse::SubmissionAttempt.transaction do
          @lighthouse_submission = Lighthouse::Submission.create(**lighthouse_submission)
          @lighthouse_submission_attempt =
            Lighthouse::SubmissionAttempt.create(submission: @lighthouse_submission,
                                                 benefits_intake_uuid: @intake_service.uuid)
        end

        Datadog::Tracing.active_trace&.set_tag('benefits_intake_uuid', @intake_service.uuid)
      end

      # VANotify job to send Submission in Progress email to veteran
      def send_submitted_email
        SurvivorsBenefits::NotificationEmail.new(@claim.id).deliver(:submitted)
      rescue => e
        monitor.track_send_email_failure(@claim, @intake_service, @user_account_uuid, 'submitted', e)
      end

      # Delete temporary stamped PDF files for this instance.
      def cleanup_file_paths
        Common::FileHelpers.delete_file_if_exists(@form_path) if @form_path
        @attachment_paths&.each { |p| Common::FileHelpers.delete_file_if_exists(p) }
        # Remove the footer-stamped PDF produced between to_stamped_pdf and process_document,
        # skipping it when process_document returned it unchanged (@form_path is deleted above).
        if @stamped_pdf_path && @stamped_pdf_path != @form_path
          Common::FileHelpers.delete_file_if_exists(@stamped_pdf_path)
        end
      rescue => e
        monitor.track_file_cleanup_error(@claim, @intake_service, @user_account_uuid, e)
      end
    end
  end
end
