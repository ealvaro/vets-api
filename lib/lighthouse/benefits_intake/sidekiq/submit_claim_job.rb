# frozen_string_literal: true

require 'sidekiq/job_retry'

require 'kafka/sidekiq/event_bus_submission_job'
require 'lighthouse/benefits_intake/metadata'
require 'lighthouse/benefits_intake/monitor'
require 'lighthouse/benefits_intake/service'
require 'pdf_utilities/pdf_stamper'
require 'pdf_fill/overflow_tracker'

module BenefitsIntake
  # generic job for submitting a claim to Lighthouse Benefits Intake
  # @see https://developer.va.gov/explore/api/benefits-intake/docs
  class SubmitClaimJob
    include Sidekiq::Job

    # generic job processing error
    class BenefitsIntakeError < StandardError; end
    # error to abort job
    class NoRetryError < StandardError; end

    # retry for 2d 1h 47m 12s
    # https://github.com/sidekiq/sidekiq/wiki/Error-Handling
    sidekiq_options retry: 16, queue: 'low'

    # retry exhaustion
    sidekiq_retries_exhausted do |msg|
      BenefitsIntake::SubmitClaimJob.exhaustion(msg)
    end

    # perform actions on submission exhaustion/no-retry
    #
    # @see ::Logging::Include::BenefitsIntake#track_submission_exhaustion
    #
    # @param msg [Hash] sidekiq exhaustion response; 'args', 'error_message' are required
    def self.exhaustion(msg)
      job_class = msg['class'].constantize || BenefitsIntake::SubmitClaimJob
      claim_class = if job_class.const_defined?(:CLAIM_CLASS)
                      job_class.const_get(:CLAIM_CLASS).constantize
                    else
                      ::SavedClaim
                    end
      saved_claim_id, user_account_uuid, participant_id = msg['args']
      claim = claim_class&.find_by(id: saved_claim_id)
      config = job_class.build_config_hash

      if claim.present? && config[:submit_kafka_event]
        user_icn = UserAccount.find_by(id: user_account_uuid)&.icn.to_s

        Kafka.submit_event(
          icn: user_icn, current_id: claim.confirmation_number.to_s,
          submission_name: claim.form_id, state: Kafka::State::ERROR,
          additional_ids: Kafka.build_additional_ids(participant_id:)
        )
      end

      monitor = job_class.new.send(:monitor)
      monitor.track_submission_exhaustion(msg, claim)
    end

    # Build the config hash
    # Subclasses should override/amend this
    #
    # @return [Hash] config hash
    def self.build_config_hash
      {
        email_type: :submitted,
        submit_kafka_event: false
      }
    end

    # Process claim pdfs and upload to Benefits Intake API
    # On success send email
    #
    # @param saved_claim_id [Integer] the claim id
    # @param user_account_uuid [String]
    # @param participant_id [String, nil]
    #
    # @return [UUID] benefits intake upload uuid
    # rubocop:disable Metrics/MethodLength
    def perform(saved_claim_id, user_account_uuid = nil, participant_id = nil)
      # for a while there we were calling this with a hash in the second argument
      # e.g. .perform_async(123, {"user_account_uuid"=>"abc"})
      # but now that we are reverting to using strings as the arguments, we
      # still need to account for any jobs already in the queue and ready
      # to retry when this code goes live. Once all 'old' jobs have been
      # processed we can remove this block of code.
      if user_account_uuid.is_a?(Hash)
        temp_hash = user_account_uuid
        user_account_uuid = temp_hash[:user_account_uuid] || temp_hash['user_account_uuid']
        participant_id = temp_hash[:participant_id] || temp_hash['participant_id']
      end

      init(saved_claim_id, user_account_uuid)

      generate_form_pdf
      generate_attachment_pdfs
      generate_metadata

      upload_claim_to_lighthouse

      submit_kafka_event(participant_id)
      send_claim_email
      monitor.track_submission_success(claim, service, user_account_uuid)
      handle_pdf_overflow_tracking

      benefits_intake_uuid
    rescue NoRetryError => e
      submission_attempt&.fail!
      msg = { 'args' => [saved_claim_id, user_account_uuid, participant_id], 'error_message' => e.message,
              'class' => self.class.name }
      BenefitsIntake::SubmitClaimJob.exhaustion(msg)
      raise ::Sidekiq::JobRetry::Skip
    rescue => e
      submission_attempt&.fail!
      monitor.track_submission_retry(claim, service, user_account_uuid, e)
      raise e
    ensure
      cleanup_file_paths
    end
    # rubocop:enable Metrics/MethodLength

    private

    attr_reader :config, :claim, :service, :form_path, :attachment_paths, :metadata, :submission, :submission_attempt

    # get the user account uuid
    def user_account_uuid
      @user_account&.id
    end

    # get the benefits intake uuid for _this_ attempt
    def benefits_intake_uuid
      @service&.uuid
    end

    # get the email type to send when job is successful
    def email_type
      @config[:email_type]
    end

    # get the stamp set to be used on the generated pdf of the claim
    def claim_stamp_set
      @config[:claim_stamp_set] || default_stamp_set
    end

    # get the stamp set to be used on the claim evidence (attachments)
    def attachment_stamp_set
      @config[:attachment_stamp_set] || default_stamp_set
    end

    # The claim class to be used
    # inheriting class may want/need to override
    def claim_class
      klass = self.class.const_get(:CLAIM_CLASS) if self.class.const_defined?(:CLAIM_CLASS)
      klass&.to_s&.constantize || ::SavedClaim
    end

    # the default stamp set to be used if none specified in config
    def default_stamp_set
      default = [{
        text: 'VA.GOV',
        timestamp: nil,
        x: 5,
        y: 5
      }]

      stamp_set = ::PDFUtilities::PDFStamper.get_stamp_set(:vagov_received_at)
      stamp_set.presence || default
    end

    # Create a monitor to be used for _this_ job
    # @see Logging::BaseMonitor
    def monitor
      @monitor ||= BenefitsIntake::Monitor.new
    end

    # Instantiate instance variables for _this_ job
    #
    # @raise [ActiveRecord::RecordNotFound] if unable to find UserAccount
    # @raise [BenefitIntakeError] if unable to find claim
    #
    # @param (see #perform)
    def init(saved_claim_id, user_account_uuid)
      @config = self.class.build_config_hash

      if user_account_uuid.present?
        @user_account = ::UserAccount.find_by(id: user_account_uuid)
        raise NoRetryError, "Unable to find ::UserAccount #{user_account_uuid}" unless @user_account
      end

      @claim = claim_class.find_by(id: saved_claim_id)
      raise NoRetryError, "Unable to find ::SavedClaim #{saved_claim_id}" unless @claim

      @service = ::BenefitsIntake::Service.new
    end

    # Create the claim PDF
    # inheriting class may want/need to override for bespoke claim `to_pdf`
    def claim_to_pdf
      claim.to_pdf
    end

    # Generate form PDF
    #
    # @return [String] path to processed PDF
    def generate_form_pdf
      @form_path = process_document(claim_to_pdf, claim_stamp_set)
    end

    # Generate the form attachment pdfs
    #
    # @return [Array<String>] path to processed PDF
    def generate_attachment_pdfs
      @attachment_paths = claim.persistent_attachments.map { |pa| process_document(pa.to_pdf, attachment_stamp_set) }
    end

    # Create a temp stamped PDF and validate the PDF satisfies Benefits Intake specification
    #
    # @param file_path [String] pdf file path
    # @param stamp_set [String|Symbol|Array<Hash>] the identifier for a stamp set or an array of stamps
    #
    # @return [String] path to stamped PDF
    def process_document(file_path, stamp_set)
      document = stamper(stamp_set).run(file_path, timestamp: claim.created_at)
      service.valid_document?(document:)
    rescue => e
      # benefits intake api enforces 60 requests per minute rate limit
      # avoid prematurely exhausting job by allowing retries if/when rate limited
      raise e if e.try(:status) == 429

      raise NoRetryError, e
    end

    # Create a stamper
    #
    # @param stamp_set [String|Symbol|Array<Hash>] the identifier for a stamp set or an array of stamps
    #
    # @return ::PDFUtilities::PDFStamper
    def stamper(stamp_set = nil)
      ::PDFUtilities::PDFStamper.new(stamp_set)
    end

    # Generate form metadata to send in upload to Benefits Intake API
    #
    # @see SavedClaim.parsed_form
    # @see BenefitsIntake::Metadata#generate
    #
    # @return [Hash] generated metadata for upload
    def generate_metadata
      # also validates/maniuplates the metadata
      @metadata = ::BenefitsIntake::Metadata.generate(
        claim.veteran_first_name,
        claim.veteran_last_name,
        claim.veteran_filenumber,
        claim.postal_code,
        self.class.name,
        claim.form_id,
        claim.business_line
      )
    rescue => e
      raise NoRetryError, e
    end

    # Upload generated pdf to Benefits Intake API
    def upload_claim_to_lighthouse
      monitor.track_submission_begun(claim, service, user_account_uuid)

      # upload must be performed within 15 minutes of this request
      service.request_upload
      lighthouse_submission_polling

      payload = {
        upload_url: service.location,
        document: form_path,
        metadata: metadata.to_json,
        attachments: attachment_paths
      }

      monitor.track_submission_attempted(claim, service, user_account_uuid, payload)
      response = service.perform_upload(**payload)
      raise BenefitsIntakeError, response.to_s unless response.success?
    end

    # Insert submission polling entries
    def lighthouse_submission_polling
      lighthouse_submission = {
        form_id: claim.form_id,
        reference_data: claim.to_json,
        saved_claim: claim
      }

      Lighthouse::SubmissionAttempt.transaction do
        @submission = Lighthouse::Submission.create(**lighthouse_submission)
        @submission_attempt = Lighthouse::SubmissionAttempt.create(submission:, benefits_intake_uuid:)
      end

      Datadog::Tracing.active_trace&.set_tag('benefits_intake_uuid', benefits_intake_uuid)
    end

    # build payload and submit SENT event to Kafka
    def submit_kafka_event(participant_id)
      return unless config[:submit_kafka_event]

      Kafka.submit_event(
        icn: @user_account&.icn.to_s,
        current_id: claim&.confirmation_number.to_s,
        submission_name: claim&.form_id,
        state: Kafka::State::SENT,
        next_id: service&.uuid.to_s,
        additional_ids: Kafka.build_additional_ids(participant_id:)
      )
    end

    # send submission success email
    # catches any error, logs but does NOT re-raise - prevent job retry
    def send_claim_email
      claim.try(:send_email, email_type) if email_type
    rescue => e
      monitor.track_send_email_failure(claim, service, user_account_uuid, email_type, e)
    end

    # Delete temporary stamped PDF files for this job instance
    # catches any error, logs but does NOT re-raise - prevent job retry
    def cleanup_file_paths
      Common::FileHelpers.delete_file_if_exists(form_path) if form_path
      attachment_paths&.each { |p| Common::FileHelpers.delete_file_if_exists(p) }
    rescue => e
      monitor.track_file_cleanup_error(claim, service, user_account_uuid, e)
    end

    # Track metrics for PDF overflow and PDF overflow by field
    def handle_pdf_overflow_tracking
      return unless @claim.track_pdf_overflow?

      tracker = PdfFill::OverflowTracker.new(@claim)
      has_overflow = tracker.track_pdf_overflow(@form_path)
      tracker.track_pdf_overflow_by_field if has_overflow && @claim.track_pdf_overflow_by_field?
    rescue
      nil
    end

    # end module BenefitsIntake
  end

  # end module BenefitsIntake
end
