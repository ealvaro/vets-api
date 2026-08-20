# frozen_string_literal: true

require 'lighthouse/benefits_intake/submission_handler/saved_claim'
require 'survivors_benefits/monitor'
require 'survivors_benefits/notification_email'
require 'bpds/sidekiq/submit_to_bpds_job'
require 'bpds/monitor'
require 'mpi/service'
require 'mpi/constants'

module SurvivorsBenefits
  module BenefitsIntake
    # @see BenefitsIntake::SubmissionHandler::SavedClaim
    class SubmissionHandler < ::BenefitsIntake::SubmissionHandler::SavedClaim
      # Retrieves all pending Lighthouse::SubmissionAttempt records associated with submissions
      # where the form_id is '21P-534EZ'.
      #
      # @return [ActiveRecord::Relation] a relation containing pending submission attempts for form '21P-534EZ'
      def self.pending_attempts
        Lighthouse::SubmissionAttempt.joins(:submission)
                                     .where(status: 'pending',
                                            'lighthouse_submissions.form_id' => SurvivorsBenefits::FORM_ID)
      end

      private

      # BenefitsIntake::SubmissionHandler::SavedClaim#claim_class
      def claim_class
        SurvivorsBenefits::SavedClaim
      end

      # BenefitsIntake::SubmissionHandler::SavedClaim#monitor
      def monitor
        @monitor ||= SurvivorsBenefits::Monitor.new
      end

      # BenefitsIntake::SubmissionHandler::SavedClaim#notification_email
      def notification_email
        @notification_email ||= SurvivorsBenefits::NotificationEmail.new(claim.id)
      end

      # handle a failure result
      # inheriting class must assign @avoided before calling `super`
      def on_failure
        @avoided = notification_email.deliver(:error)
        super
      end

      # handle a success result
      def on_success
        notification_email.deliver(:received)
        result = super
        submit_to_bpds_after_vbms if bpds_after_vbms_enabled?
        result
      end

      # handle a stale result
      def on_stale
        true
      end

      # True when the after-VBMS BPDS submission path is enabled. Evaluated without
      # an actor because the poller has no current_user.
      def bpds_after_vbms_enabled?
        Flipper.enabled?(:bpds_service_enabled) &&
          Flipper.enabled?(:survivors_benefits_bpds_service_enabled) &&
          Flipper.enabled?(:survivors_benefits_bpds_submit_after_vbms)
      end

      # Resolves identifiers from claim state (no current_user available in the
      # poller context) and enqueues the BPDS submission job. Skips with a tracked
      # metric when no usable identifier is found.
      def submit_to_bpds_after_vbms
        claim_id = claim.id
        form_id = claim.form_id
        bpds_monitor.track_service_begun(claim_id, form_id)
        payload = bpds_identifiers_for_claim

        if payload.blank?
          bpds_monitor.track_skip_bpds_job(claim_id, form_id, nil)
          return
        end

        encrypted_payload = KmsEncrypted::Box.new.encrypt(payload.to_json)
        bpds_monitor.track_submit_begun(claim_id, form_id, bpds_payload_metrics(payload))
        ::BPDS::Sidekiq::SubmitToBPDSJob.perform_async(claim_id, encrypted_payload)
      rescue => e
        # BPDS is experimental and must never disrupt claim submission. This runs after VBMS
        # confirmation (the claim and structured data have already been transmitted, the
        # received email sent, and the attempt marked vbms!), so we swallow any failure here
        # rather than relying on the poller's rescue. This keeps a BPDS error from affecting
        # this claim's handling or other claims in the same SubmissionStatusJob batch.
        bpds_monitor.track_submit_failure(claim_id, form_id, e)
      end

      # Tries MPI lookup using the claim's stored user_account ICN, then falls
      # back to identifiers carried on the parsed form.
      #
      # @return [Hash] identifier payload (may be empty)
      def bpds_identifiers_for_claim
        identifiers = mpi_identifiers_from_claim.dup

        if (file_number = claim.parsed_form['vaFileNumber']).present?
          identifiers[:file_number] ||= file_number
        end

        if (ssn = claim.parsed_form['veteranSocialSecurityNumber']).present?
          identifiers[:ssn] ||= ssn
          identifiers[:file_number] ||= ssn
        end

        bpds_monitor.track_get_user_identifier_file_number_result(identifiers[:file_number].present?)
        identifiers.compact_blank
      end

      # MPI lookup using claim.user_account.icn (when present).
      #
      # @return [Hash] hash with participant_id/ssn/edipi/icn keys (may be empty)
      def mpi_identifiers_from_claim
        icn = claim.respond_to?(:user_account) ? claim.user_account&.icn : nil
        return {} if icn.blank?

        bpds_monitor.track_get_user_identifier('loa3')
        response = MPI::Service.new.find_profile_by_identifier(identifier: icn,
                                                               identifier_type: MPI::Constants::ICN)
        participant_id = response.profile&.participant_id
        ssn = response.profile&.ssn
        bpds_monitor.track_get_user_identifier_result('mpi', participant_id.present?, ssn.present?)

        { participant_id:, ssn:, icn:, edipi: response.profile&.edipi }
      end

      def bpds_payload_metrics(payload)
        {
          participant_id_present: payload[:participant_id].present?,
          file_number_present: payload[:file_number].present?,
          ssn_present: payload[:ssn].present?,
          icn_present: payload[:icn].present?,
          edipi_present: payload[:edipi].present?
        }
      end

      def bpds_monitor
        @bpds_monitor ||= ::BPDS::Monitor.new
      end
    end
  end
end
