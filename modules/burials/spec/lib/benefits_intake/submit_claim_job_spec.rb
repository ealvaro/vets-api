# frozen_string_literal: true

require 'rails_helper'

require 'lighthouse/benefits_intake/service'
require 'lighthouse/benefits_intake/metadata'
require 'burials/benefits_intake/submit_claim_job'
require 'burials/monitor'
require 'burials/notification_email'

RSpec.describe Burials::BenefitsIntake::SubmitClaimJob, :uploader_helpers do
  stub_virus_scan

  let(:job) { described_class.new }
  let(:claim) { create(:burials_saved_claim) }
  let(:service) { double('service') }
  let(:monitor) { Burials::Monitor.new }
  let(:user_account) { double('user_account', id: SecureRandom.uuid, icn: 'FOOBAR') }

  describe '.build_config_hash' do
    it 'returns hash of job config options' do
      allow(Flipper).to receive(:enabled?).with(:burial_kafka_event_enabled).and_return(false)
      expect(described_class.build_config_hash).to eq(
        { email_type: :submitted,
          claim_stamp_set: :burials_generated_claim,
          attachment_stamp_set: :burials_received_at,
          submit_kafka_event: false }
      )
    end
  end

  describe '#claim_to_pdf' do
    let(:pdf_path) { 'random/path/to/pdf' }

    before do
      job.instance_variable_set(:@claim, claim)
      allow(claim).to receive(:to_pdf).and_return(pdf_path)
    end

    it 'generates PDF with redesign options' do
      expect(claim).to receive(:to_pdf).with(claim.id, { extras_redesign: true, omit_esign_stamp: true })

      result = job.send(:claim_to_pdf)
      expect(result).to eq(pdf_path)
    end
  end

  describe 'sidekiq_retries_exhausted block' do
    before do
      allow(Burials::Monitor).to receive(:new).and_return(monitor)
      allow(Flipper).to receive(:enabled?).with(:burial_kafka_event_enabled).and_return(false)
    end

    context 'when retries are exhausted' do
      it 'logs a distinct error when no claim_id provided' do
        msg = { 'args' => [], 'class' => 'Burials::BenefitsIntake::SubmitClaimJob', 'error_message' => 'An error occurred', 'queue' => 'low' }
        Burials::BenefitsIntake::SubmitClaimJob.within_sidekiq_retries_exhausted_block do
          expect(monitor).to receive(:track_submission_exhaustion).with(msg, nil)
        end
      end

      it 'logs a distinct error when only claim_id provided' do
        config = { claim_class: 'Burials::SavedClaim' }
        msg = { 'args' => [claim.id, config], 'class' => 'Burials::BenefitsIntake::SubmitClaimJob', 'error_message' => 'An error occurred', 'queue' => 'low' }
        Burials::BenefitsIntake::SubmitClaimJob.within_sidekiq_retries_exhausted_block(msg) do
          expect(SavedClaim).to receive(:find_by).with(id: claim.id).and_return(claim)

          expect(monitor).to receive(:track_submission_exhaustion).with(msg, claim)
        end
      end
    end
  end

  # Rspec.describe
end
