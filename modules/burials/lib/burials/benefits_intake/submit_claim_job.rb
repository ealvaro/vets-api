# frozen_string_literal: true

require 'burials/monitor'
require 'burials/pdf_stamper'
require 'lighthouse/benefits_intake/sidekiq/submit_claim_job'

module Burials
  module BenefitsIntake
    # sidekiq job to send pdfs to Lighthouse:BenefitsIntake API
    # @see https://developer.va.gov/explore/api/benefits-intake/docs
    class SubmitClaimJob < ::BenefitsIntake::SubmitClaimJob
      # Process claim pdfs and upload to Benefits Intake API
      # On success send email
      #
      # @param saved_claim_id [Integer] the claim id
      # @param user_account_uuid [UUID] the user submitting the form
      #
      # @return [UUID] benefits intake upload uuid
      def perform(saved_claim_id, user_account_uuid = nil)
        config = {
          claim_class: 'Burials::SavedClaim',
          user_account_uuid:,
          email_type: :submitted,
          claim_stamp_set: :burials_generated_claim,
          attachment_stamp_set: :burials_received_at,
          source: self.class.to_s,
          submit_kafka_event: Flipper.enabled?(:burial_kafka_event_enabled)
        }
        super(saved_claim_id, **config)
      end

      private

      # @see ::BenefitsIntake::SubmitClaimJob#monitor
      # @see Burials::Monitor
      def monitor
        @monitor ||= Burials::Monitor.new
      end

      # @see ::BenefitsIntake::SubmitClaimJob#stamper
      def stamper(stamp_set = nil)
        Burials::PDFStamper.new(stamp_set)
      end

      # @see ::BenefitsIntake::SubmitClaimJob#claim_to_pdf
      def claim_to_pdf
        @claim.to_pdf(@claim.id, { extras_redesign: true, omit_esign_stamp: true })
      end
    end
  end
end
