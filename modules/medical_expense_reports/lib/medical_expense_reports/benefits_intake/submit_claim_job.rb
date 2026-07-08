# frozen_string_literal: true

require 'ibm/service'
require 'lighthouse/benefits_intake/service'
require 'lighthouse/benefits_intake/metadata'
require 'medical_expense_reports/notification_email'
require 'medical_expense_reports/monitor'
require 'medical_expense_reports/pdf_fill/va21p8416'
require 'pdf_utilities/datestamp_pdf'

require 'bigdecimal'
require 'date'

module MedicalExpenseReports
  module BenefitsIntake
    # Sidekiq job to send pension pdf to Lighthouse:BenefitsIntake API
    # @see https://developer.va.gov/explore/api/benefits-intake/docs
    class SubmitClaimJob
      include Sidekiq::Job

      # Error if "Unable to find MedicalExpenseReports::SavedClaim"
      class MedicalExpenseReportsBenefitIntakeError < StandardError; end

      # retry for  2d 1h 47m 12s
      # https://github.com/sidekiq/sidekiq/wiki/Error-Handling
      sidekiq_options retry: 16, queue: 'low'
      sidekiq_retries_exhausted do |msg|
        ia_monitor = MedicalExpenseReports::Monitor.new
        begin
          claim = MedicalExpenseReports::SavedClaim.find(msg['args'].first)
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
      # @param current_loa [Integer, nil] the submitter's current Level of Assurance, used to stamp
      #   the authentication level in the PDF footer watermark (nil when unauthenticated)
      #
      # @return [UUID] benefits intake upload uuid
      #
      def perform(saved_claim_id, user_account_uuid = nil, current_loa = nil)
        return unless Flipper.enabled?(:medical_expense_reports_form_enabled)

        @current_loa = current_loa
        @intermediate_pdf_paths = []
        init(saved_claim_id, user_account_uuid)
        # benefits_intake_uuid comes from here
        @intake_service ||= reset_intake_service

        process_submission
      rescue => e
        monitor.track_submission_retry(@claim, @intake_service, @user_account_uuid, e)
        @lighthouse_submission_attempt&.fail!
        raise e
      ensure
        cleanup_file_paths
      end

      private

      ##
      # Handle the document generation, upload flow, and post-submission hooks.
      #
      # @return [String] the intake service UUID for the submission
      def process_submission
        # generate and validate claim pdf documents.
        # omit_esign_stamp/omit_footer suppress the shared machinery's hardcoded-IAL2 footer so we can
        # stamp a footer whose authentication level reflects the submitter's actual LOA on every page.
        raw_pdf = @claim.to_pdf(@claim.id, extras_redesign: true, omit_esign_stamp: true, omit_footer: true)
        @intermediate_pdf_paths << raw_pdf
        stamped_pdf = MedicalExpenseReports::PdfFill::Va21p8416.stamp_submission_footer(
          raw_pdf, @claim.created_at, footer_loa
        )
        @intermediate_pdf_paths << stamped_pdf
        @form_path = process_document(stamped_pdf)
        @attachment_paths = @claim.persistent_attachments.map { |pa| process_document(pa.to_pdf) }
        form = @claim.parsed_form
        @metadata = generate_metadata(form)
        @ibm_payload = @claim.to_ibm if Flipper.enabled?(:medical_expense_reports_structured_data_transmission)

        # upload must be performed within 15 minutes of this request
        upload_document

        send_submitted_email
        monitor.track_submission_success(@claim, @intake_service, @user_account_uuid)

        @intake_service.uuid
      end

      # LOA used for the footer authentication stamp. Falls back to LOA 1 (signed in) for an
      # authenticated submitter whose LOA is missing or non-positive — e.g. a job enqueued before the
      # current_loa argument existed and replayed during a deploy — so authenticated submitters are
      # never stamped "not signed in". Remains nil for unauthenticated submitters.
      #
      # @return [Integer, nil]
      def footer_loa
        return @current_loa if @current_loa.to_i.positive?

        @user_account_uuid.present? ? 1 : nil
      end

      # Number of in-home care rows IBM expects.
      IN_HOME_ROW_COUNT = 8

      # Number of medical expense rows IBM expects.
      MED_EXPENSE_ROW_COUNT = 14

      # Number of travel rows IBM expects.
      TRAVEL_ROW_COUNT = 12

      # Normalize values that represent child/dependent recipients.
      CHILD_RECIPIENTS = %w[CHILD DEPENDENT].freeze

      # Instantiate instance variables for _this_ job
      def init(saved_claim_id, user_account_uuid)
        @user_account_uuid = user_account_uuid
        @user_account = UserAccount.find(@user_account_uuid) if @user_account_uuid.present?
        # UserAccount.find will raise an error if unable to find the user_account record

        @claim = MedicalExpenseReports::SavedClaim.find(saved_claim_id)
        unless @claim
          raise MedicalExpenseReportsBenefitIntakeError,
                "Unable to find MedicalExpenseReports::SavedClaim #{saved_claim_id}"
        end
      end

      # Create a monitor to be used for _this_ job
      # @see MedicalExpenseReports::Monitor
      def monitor
        @monitor ||= MedicalExpenseReports::Monitor.new
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
      # Generate metadata for Benefits Intake upload, deriving veteran and claimant details.
      #
      # @param form [Hash]
      # @return [Hash]
      def generate_metadata(form)
        address = form['claimantAddress'] || form['veteranAddress']

        # also validates/manipulates the metadata
        ::BenefitsIntake::Metadata.generate(
          form['veteranFullName']['first'],
          form['veteranFullName']['last'],
          form['vaFileNumber'] || form['veteranSocialSecurityNumber'],
          address['postalCode'],
          'va_gov_bio_huntridge',
          "StructuredData:#{@claim.form_id}",
          @claim.business_line
        )
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
        govcio_upload if response.success? && @ibm_payload.present?

        raise MedicalExpenseReportsBenefitIntakeError, response.to_s unless response.success?
      end

      # MyVA relies on SubmissionAttempt records to find submitted forms and create Submission
      # in Progress cards on the MyVA page
      #
      # @return SubmissionAttempt
      def update_form_submission_attempt
        # If its a retry we need the new intake uuid for the submission
        form_submission = @claim.form_submissions.order(created_at: :asc).last || FormSubmission.create_with(
          form_type: @claim.form_id,
          form_data: @claim.to_json,
          saved_claim: @claim,
          saved_claim_id: @claim.id,
          user_account_id: @claim.user_account_id
        ).find_or_create_by!(form_type: @claim.form_id, saved_claim_id: @claim.id)

        # update the submission attempt as well
        latest_form_submission_attempt = form_submission.latest_attempt
        if latest_form_submission_attempt
          latest_form_submission_attempt.update!(benefits_intake_uuid: @intake_service.uuid)
        else
          FormSubmissionAttempt.create_with(
            form_submission:
          ).find_or_create_by!(benefits_intake_uuid: @intake_service.uuid)
        end
      end

      # Create a new instance of the Benefits Intake service for this job
      #
      # @return BenefitsIntake::Service
      def reset_intake_service
        @intake_service = ::BenefitsIntake::Service.new
      end

      # Upload to IBM MMS if the govcio flipper is enabled
      def govcio_upload
        return unless Flipper.enabled?(:medical_expense_reports_structured_data_transmission)

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
        MedicalExpenseReports::NotificationEmail.new(@claim.id).deliver(:submitted)
      rescue => e
        monitor.track_send_email_failure(@claim, @intake_service, @user_account_uuid, 'submitted', e)
      end

      # Delete temporary stamped PDF files for this instance.
      def cleanup_file_paths
        Common::FileHelpers.delete_file_if_exists(@form_path) if @form_path
        @attachment_paths&.each { |p| Common::FileHelpers.delete_file_if_exists(p) }
        # Remove the intermediate PDFs produced between to_pdf and process_document (the raw fill and
        # the footer-stamped copy), skipping @form_path which is deleted above.
        @intermediate_pdf_paths&.each do |p|
          Common::FileHelpers.delete_file_if_exists(p) unless p == @form_path
        end
      rescue => e
        monitor.track_file_cleanup_error(@claim, @intake_service, @user_account_uuid, e)
      end
    end
  end
end
