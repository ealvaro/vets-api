# frozen_string_literal: true

require 'rails_helper'
require 'lighthouse/benefits_intake/service'
require 'income_and_assets/benefits_intake/submit_claim_job'
require 'income_and_assets/monitor'
require 'pdf_utilities/datestamp_pdf'

RSpec.describe IncomeAndAssets::BenefitsIntake::SubmitClaimJob, :uploader_helpers do
  stub_virus_scan

  let(:job) { described_class.new }
  let(:claim) { build_stubbed(:income_and_assets_claim) }
  let(:service) { double('service') }
  let(:monitor) { IncomeAndAssets::Monitor.new }
  let(:user_account) { double('user_account', id: SecureRandom.uuid, icn: 'FOOBAR') }
  let(:generated_metadata) do
    {
      'veteranFirstName' => claim.veteran_first_name,
      'veteranLastName' => claim.veteran_last_name,
      'fileNumber' => claim.veteran_filenumber,
      'zipCode' => '00000',
      'source' => job.class.to_s,
      'docType' => claim.form_id,
      'businessLine' => claim.business_line
    }
  end

  describe '.build_config_hash' do
    it 'returns hash of job config options' do
      allow(Flipper).to receive(:enabled?).with(:income_and_assets_kafka_event_enabled).and_return(false)
      user = build(:user)
      expect(described_class.build_config_hash(user)).to eq(
        {
          user_account_uuid: user.user_account.id,
          participant_id: user.participant_id,
          email_type: :submitted,
          claim_stamp_set: :income_and_assets_generated_claim,
          attachment_stamp_set: :income_and_assets_received_at,
          submit_kafka_event: false
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
      allow(IncomeAndAssets::Monitor).to receive(:new).and_return(monitor)
    end

    context 'when retries are exhausted' do
      it 'logs a distrinct error when no claim_id provided' do
        msg = { 'args' => [], 'class' => 'IncomeAndAssets::BenefitsIntake::SubmitClaimJob', 'error_message' => 'An error occurred', 'queue' => 'low' }
        IncomeAndAssets::BenefitsIntake::SubmitClaimJob.within_sidekiq_retries_exhausted_block do
          expect(monitor).to receive(:track_submission_exhaustion).with(msg, nil)
        end
      end

      it 'logs a distinct error when only claim_id provided' do
        config = { email_type: :submitted }
        msg = { 'args' => [claim.id, config], 'class' => 'IncomeAndAssets::BenefitsIntake::SubmitClaimJob', 'error_message' => 'An error occurred', 'queue' => 'low' }
        IncomeAndAssets::BenefitsIntake::SubmitClaimJob.within_sidekiq_retries_exhausted_block(msg) do
          expect(SavedClaim).to receive(:find_by).with(id: claim.id).and_return(claim)

          expect(monitor).to receive(:track_submission_exhaustion).with(msg, claim)
        end
      end
    end
  end
end
