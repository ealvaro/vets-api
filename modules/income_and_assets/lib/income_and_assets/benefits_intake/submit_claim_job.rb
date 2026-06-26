# frozen_string_literal: true

require 'income_and_assets/monitor'
require 'income_and_assets/pdf_stamper'
require 'lighthouse/benefits_intake/sidekiq/submit_claim_job'

module IncomeAndAssets
  module BenefitsIntake
    # sidekiq job to send pdfs to Lighthouse:BenefitsIntake API
    # @see https://developer.va.gov/explore/api/benefits-intake/docs
    class SubmitClaimJob < ::BenefitsIntake::SubmitClaimJob
      CLAIM_CLASS = 'IncomeAndAssets::SavedClaim' # single table inheritance issue

      # @see ::BenefitsIntake::SubmitClaimJob#build_config_hash
      #
      # @return [Hash] config for processing benefits intake submission
      def self.build_config_hash
        {
          email_type: :submitted,
          claim_stamp_set: :income_and_assets_generated_claim,
          attachment_stamp_set: :income_and_assets_received_at,
          submit_kafka_event: Flipper.enabled?(:income_and_assets_kafka_event_enabled)
        }
      end

      private

      # @see ::BenefitsIntake::SubmitClaimJob#monitor
      # @see IncomeAndAssets::Monitor
      def monitor
        @monitor ||= IncomeAndAssets::Monitor.new
      end

      # @see ::BenefitsIntake::SubmitClaimJob#stamper
      def stamper(stamp_set = nil)
        IncomeAndAssets::PDFStamper.new(stamp_set)
      end

      # @see ::BenefitsIntake::SubmitClaimJob#claim_to_pdf
      def claim_to_pdf
        @claim.to_pdf(@claim.id, { extras_redesign: true, omit_esign_stamp: true })
      end
    end
  end
end
