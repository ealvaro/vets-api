# frozen_string_literal: true

require 'lighthouse/benefits_intake/sidekiq/submit_claim_job'
require 'pensions/monitor'
require 'pensions/pdf_stamper'

module Pensions
  module BenefitsIntake
    # sidekiq job to send pdfs to Lighthouse:BenefitsIntake API
    # @see https://developer.va.gov/explore/api/benefits-intake/docs
    class SubmitClaimJob < ::BenefitsIntake::SubmitClaimJob
      # Process claim pdfs and upload to Benefits Intake API
      # On success send confirmation email
      #
      # @param saved_claim_id [Integer] the pension claim id
      # @param user_account_uuid [UUID] the user submitting the form
      # @param participant_id [String, nil] the participant ID for Kafka event traceability
      #
      # @return [UUID] benefits intake upload uuid
      def perform(saved_claim_id, user_account_uuid = nil, participant_id = nil)
        config = {
          claim_class: 'Pensions::SavedClaim',
          user_account_uuid:,
          participant_id:,
          email_type: :submitted,
          claim_stamp_set: :pensions_generated_claim,
          attachment_stamp_set: :pensions_received_at,
          source: self.class.to_s,
          submit_kafka_event: true # always submit Kafka event for pensions claims
        }
        super(saved_claim_id, **config)
      end

      private

      # @see ::BenefitsIntake::SubmitClaimJob#monitor
      # @see Pensions::Monitor
      def monitor
        @monitor ||= Pensions::Monitor.new
      end

      # @see ::BenefitsIntake::SubmitClaimJob#stamper
      def stamper(stamp_set = nil)
        Pensions::PDFStamper.new(stamp_set)
      end

      # @see ::BenefitsIntake::SubmitClaimJob#claim_to_pdf
      def claim_to_pdf
        @claim.to_pdf(@claim.id, { extras_redesign: true, omit_esign_stamp: true })
      end
    end
  end
end
