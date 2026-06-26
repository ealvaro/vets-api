# frozen_string_literal: true

require 'rails_helper'

require 'kafka/sidekiq/event_bus_submission_job'
require 'lighthouse/benefits_intake/service'
require 'lighthouse/benefits_intake/metadata'
require 'pensions/benefits_intake/submit_claim_job'
require 'pensions/monitor'
require 'pensions/notification_email'

RSpec.describe Pensions::BenefitsIntake::SubmitClaimJob, :uploader_helpers do
  stub_virus_scan

  let(:job) { described_class.new }
  let(:claim) { build_stubbed(:pensions_saved_claim) }
  let(:service) { double('service') }
  let(:monitor) { Pensions::Monitor.new }
  let(:user_account) { double('user_account', id: SecureRandom.uuid, icn: 'FOOBAR') }

  describe '.build_config_hash' do
    it 'returns hash of job config options' do
      expect(described_class.build_config_hash).to eq(
        {
          email_type: :submitted,
          claim_stamp_set: :pensions_generated_claim,
          attachment_stamp_set: :pensions_received_at,
          submit_kafka_event: true
        }
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
      allow(Pensions::Monitor).to receive(:new).and_return(monitor)
    end

    context 'when retries are exhausted' do
      it 'logs a distinct error when no claim_id provided' do
        msg = { 'args' => [], 'class' => 'Pensions::BenefitsIntake::SubmitClaimJob', 'error_message' => 'An error occurred', 'queue' => 'low' }
        Pensions::BenefitsIntake::SubmitClaimJob.within_sidekiq_retries_exhausted_block do
          expect(monitor).to receive(:track_submission_exhaustion).with(msg, nil)
        end
      end

      it 'logs a distinct error when only claim_id provided' do
        config = { claim_class: 'Pensions::SavedClaim' }
        msg = { 'args' => [claim.id, config], 'class' => 'Pensions::BenefitsIntake::SubmitClaimJob', 'error_message' => 'An error occurred', 'queue' => 'low' }
        Pensions::BenefitsIntake::SubmitClaimJob.within_sidekiq_retries_exhausted_block(msg) do
          expect(SavedClaim).to receive(:find_by).with(id: claim.id).and_return(claim)

          expect(monitor).to receive(:track_submission_exhaustion).with(msg, claim)
        end
      end
    end
  end

  # Rspec.describe
end
