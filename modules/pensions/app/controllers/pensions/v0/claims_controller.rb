# frozen_string_literal: true

require 'bpds/submission_handler'
require 'kafka/concerns/kafka'
require 'pensions/benefits_intake/submit_claim_job'
require 'pensions/monitor'
require 'persistent_attachments/sanitizer'

module Pensions
  module V0
    ##
    # The pensions claim controller that handles form submissions
    #
    class ClaimsController < ApplicationController
      include ::BPDS::SubmissionHandler

      skip_before_action :authenticate, except: :create
      before_action :load_user, only: :create

      service_tag 'pension-application'

      # an identifier that matches the parameter that the form will be set as in the JSON submission.
      def short_name
        'pension_claim'
      end

      ##
      # a subclass of SavedClaim, runs json-schema validations and performs any storage and attachment processing
      #
      def claim_class
        Pensions::SavedClaim
      end

      ##
      # GET serialized pension form data
      #
      def show
        claim = claim_class.find_by!(guid: params[:id]) # raises ActiveRecord::RecordNotFound
        render json: SavedClaimSerializer.new(claim)
      rescue ActiveRecord::RecordNotFound => e
        monitor.track_show404(params[:id], current_user, e)
        render(json: { error: e.to_s }, status: :not_found)
      rescue => e
        monitor.track_show_error(params[:id], current_user, e)
        raise e
      end

      # POST creates and validates an instance of `claim_class`
      def create
        claim = create_claim(filtered_params[:form])
        monitor.track_create_attempt(claim, current_user)

        in_progress_form = current_user ? InProgressForm.form_for_user(claim.form_id, current_user) : nil
        claim.form_start_date = in_progress_form.created_at if in_progress_form

        unless claim.save
          monitor.track_create_validation_error(in_progress_form, claim, current_user)
          log_validation_error_to_metadata(in_progress_form, claim)
          raise Common::Exceptions::ValidationErrors, claim.errors
        end

        submit_traceability_to_event_bus(claim)

        # See BPDS::SubmissionHandler
        submit_claim_to_bpds(claim.id, claim.form_id, current_user)

        process_attachments(in_progress_form, claim)

        Pensions::BenefitsIntake::SubmitClaimJob.perform_async(claim.id, current_user&.user_account_uuid,
                                                               current_user&.participant_id)

        monitor.track_create_success(in_progress_form, claim, current_user)

        clear_saved_form(claim.form_id)
        render json: SavedClaimSerializer.new(claim)
      rescue => e
        monitor.track_create_error(in_progress_form, claim, current_user, e)
        raise e
      end

      private

      # Creates a new claim instance with the provided form parameters.
      #
      # @param form_params [Hash] The parameters for the claim form.
      # @return [Claim] A new instance of the claim class initialized with the given attributes.
      #   If the current user has an associated user account, it is included in the claim attributes.
      def create_claim(form_params)
        claim_attributes = { form: form_params }
        claim_attributes[:user_account] = @current_user.user_account if @current_user&.user_account

        claim = claim_class.new(**claim_attributes)

        begin
          form_params = JSON.parse(claim.form)
          form_params['signatureDate'] = Time.zone.today.strftime('%Y-%m-%d')
          claim.form = form_params.to_json
        rescue => e
          metric = "#{Pensions::Monitor::CLAIM_STATS_KEY}.claim_signature_error"
          monitor.track_request(:error, 'Pensions claim signature error', metric, error: e.message, claim_id: claim.id)
        end

        claim
      end

      # Build payload and submit to EventBusSubmissionJob
      #
      # @param claim [Pensions::SavedClaim]
      def submit_traceability_to_event_bus(claim)
        Kafka.submit_event(
          icn: current_user&.icn.to_s,
          current_id: claim&.confirmation_number.to_s,
          submission_name: Pensions::FORM_ID,
          state: Kafka::State::RECEIVED,
          additional_ids: Kafka.build_additional_ids(participant_id: current_user&.participant_id)
        )
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
        sanitize_attachments(claim, in_progress_form)
        raise e
      end

      # Filters out the parameters to form access.
      def filtered_params
        params.require(short_name.to_sym).permit(:form)
      end

      # include validation error on in_progress_form metadata.
      # `noop` if in_progress_form is `blank?`
      #
      # @param in_progress_form [InProgressForm]
      # @param claim [Pensions::SavedClaim]
      def log_validation_error_to_metadata(in_progress_form, claim)
        return if in_progress_form.blank?

        metadata = in_progress_form.metadata
        metadata['submission']['error_message'] = claim&.errors&.errors&.to_s
        in_progress_form.update(metadata:)
      end

      ##
      # Sanitizes attachments for a claim and handles persistent attachment errors.
      #
      # This method checks a feature flag to determine if
      # persistent attachment error handling should be enabled. If enabled, it:
      #   - Calls the PersistentAttachments::Sanitizer to remove bad attachments and update the in_progress_form.
      #   - Sends a persistent attachment error email notification if the claim supports it.
      #   - Destroys the claim if attachment processing fails.
      #
      # @param claim [Pensions::SavedClaim] The claim whose attachments are being sanitized.
      # @param in_progress_form [InProgressForm] The in-progress form associated with the claim.
      # @return [void]
      def sanitize_attachments(claim, in_progress_form)
        feature_flag = Settings.vanotify.services['21p_527ez'].email.persistent_attachment_error.flipper_id

        if Flipper.enabled?(feature_flag.to_sym)
          PersistentAttachments::Sanitizer.new.sanitize_attachments(claim, in_progress_form)
          claim.send_email(:persistent_attachment_error) if claim.respond_to?(:send_email)
          claim.destroy! # Handle deletion of the claim if attachments processing fails
        end
      end

      ##
      # retrieve a monitor for tracking
      #
      # @return [Pensions::Monitor]
      #
      def monitor
        @monitor ||= Pensions::Monitor.new
      end
    end
  end
end
