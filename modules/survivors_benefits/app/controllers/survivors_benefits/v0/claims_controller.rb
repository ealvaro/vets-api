# frozen_string_literal: true

require 'bpds/submission_handler'
require 'survivors_benefits/benefits_intake/submit_claim_job'
require 'survivors_benefits/monitor'
require 'survivors_benefits/zsf_config'
require 'persistent_attachments/sanitizer'

module SurvivorsBenefits
  module V0
    ###
    # The Survivors Benefits claim controller that handles form submissions
    #
    class ClaimsController < ClaimsBaseController
      include PdfS3Operations
      include BPDS::SubmissionHandler

      before_action :check_flipper_flag
      skip_after_action :set_csrf_header, only: [:create]
      service_tag 'survivors-benefits'

      # an identifier that matches the parameter that the form will be set as in the JSON submission.
      def short_name
        'survivors_benefits_claim'
      end

      # a subclass of SavedClaim, runs json-schema validations and performs any storage and attachment processing
      def claim_class
        SurvivorsBenefits::SavedClaim
      end

      # GET serialized survivors benefits form data
      def show
        claim = claim_class.find_by!(guid: params[:id]) # raises ActiveRecord::RecordNotFound
        form_submission_attempt = last_form_submission_attempt(claim.guid)

        raise Common::Exceptions::RecordNotFound, params[:id] if form_submission_attempt.nil?

        pdf_url = s3_signed_url(claim, form_submission_attempt.created_at.to_date, config: SurvivorsBenefits::ZsfConfig.new)
        render json: ArchivedClaimSerializer.new(claim, params: { pdf_url: })
      rescue ActiveRecord::RecordNotFound => e
        monitor.track_show404(params[:id], current_user, e)
        render(json: { error: e.to_s }, status: :not_found)
      rescue => e
        monitor.track_show_error(params[:id], current_user, e)
        raise e
      end

      # POST creates and validates an instance of `claim_class`
      def create
        claim = claim_class.new(form: filtered_params[:form], user_account: current_user&.user_account)
        monitor.track_create_attempt(claim, current_user)

        in_progress_form = current_user ? InProgressForm.form_for_user(claim.form_id, current_user) : nil
        claim.form_start_date = in_progress_form.created_at if in_progress_form

        unless claim.save
          monitor.track_create_validation_error(in_progress_form, claim, current_user)
          log_validation_error_to_metadata(in_progress_form, claim)
          raise Common::Exceptions::ValidationErrors, claim.errors
        end

        process_attachments(in_progress_form, claim)

        # Parallel BPDS submission (matches the 21P-527EZ pattern). No-op when the
        # per-form flag is off OR when the after-VBMS mode is on (in which case the
        # SubmissionHandler enqueues BPDS after the Lighthouse poller marks VBMS).
        #
        # BPDS is experimental and must never disrupt claim submission. submit_claim_to_bpds
        # runs synchronously here and performs MPI/BGS lookups and KMS encryption before
        # enqueuing the async job, any of which can raise. We swallow those errors so the
        # claim is still handed off to SubmitClaimJob below.
        submit_claim_to_bpds_safely(claim) if survivors_benefits_bpds_parallel_enabled?

        SurvivorsBenefits::BenefitsIntake::SubmitClaimJob.perform_async(claim.id, current_user&.user_account_uuid)

        monitor.track_create_success(in_progress_form, claim, current_user)

        clear_saved_form(claim.form_id)

        pdf_url = stamped_pdf_url(claim)

        render json: ArchivedClaimSerializer.new(claim, params: { pdf_url: })
      rescue => e
        monitor.track_create_error(in_progress_form, claim, current_user, e)
        raise e
      end

      private

      # Uploads the completed form to S3 for the confirmation-page download link and returns the
      # presigned URL. The download copy must carry the same submission watermark as the Benefits
      # Intake upload, so it is generated stamped rather than letting upload_to_s3 fall back to the
      # default unstamped claim.to_pdf.
      #
      # @param claim [SurvivorsBenefits::SavedClaim]
      # @return [String] presigned S3 URL for the stamped PDF
      def stamped_pdf_url(claim)
        upload_to_s3(
          claim,
          config: SurvivorsBenefits::ZsfConfig.new,
          pdf_path: claim.to_stamped_pdf(claim.guid)
        )
      end

      # Raises an exception if the survivors benefits flipper flag isn't enabled.
      def check_flipper_flag
        raise Common::Exceptions::Forbidden unless Flipper.enabled?(:survivors_benefits_form_enabled,
                                                                    current_user)
      end

      ##
      # Processes attachments for the claim
      #
      # @param in_progress_form [Object]
      # @param claim
      # @raise [Exception]
      def process_attachments(in_progress_form, claim)
        claim.process_attachments!
      rescue => e
        monitor.track_process_attachment_error(in_progress_form, claim, current_user)
        raise e
      end

      # Filters out the parameters to form access.
      def filtered_params
        params.require(short_name.to_sym).permit(:form)
      end

      ##
      # include validation error on in_progress_form metadata.
      # `noop` if in_progress_form is `blank?`
      #
      # @param in_progress_form [InProgressForm]
      # @param claim [SurvivorsBenefits::SavedClaim]
      #
      def log_validation_error_to_metadata(in_progress_form, claim)
        return if in_progress_form.blank?

        metadata = in_progress_form.metadata
        metadata['submission']['error_message'] = claim&.errors&.errors&.to_s
        in_progress_form.update(metadata:)
      end

      # Invokes the BPDS submission, isolating any failure so it cannot abort claim
      # submission. A raised error here would otherwise propagate to #create's rescue
      # and prevent SubmitClaimJob from ever being enqueued, orphaning the saved claim.
      #
      # @param claim [SurvivorsBenefits::SavedClaim]
      def submit_claim_to_bpds_safely(claim)
        submit_claim_to_bpds(claim.id, claim.form_id, current_user)
      rescue => e
        bpds_monitor.track_submit_failure(claim.id, claim.form_id, e)
        Rails.logger.warn('[SurvivorsBenefits] BPDS parallel submission failed; claim submission continues',
                          claim_id: claim.id, exception: e)
      end

      # True when the per-form BPDS flag is on AND the after-VBMS timing flag is off.
      # The master :bpds_service_enabled flag is checked inside BPDS::SubmissionHandler#submit_claim_to_bpds.
      def survivors_benefits_bpds_parallel_enabled?
        Flipper.enabled?(:survivors_benefits_bpds_service_enabled, current_user) &&
          !Flipper.enabled?(:survivors_benefits_bpds_submit_after_vbms, current_user)
      end

      ##
      # retreive a monitor for tracking
      #
      # @return [SurvivorsBenefits::Monitor]
      #
      def monitor
        @monitor ||= SurvivorsBenefits::Monitor.new
      end
    end
  end
end
