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

  describe '#perform' do
    let(:response) { double('response') }
    let(:pdf_path) { 'random/path/to/pdf' }
    let(:location) { 'test_location' }
    let(:omit_esign_stamp) { true }
    let(:extras_redesign) { true }

    before do
      allow(Flipper).to receive(:enabled?).with(:income_and_assets_kafka_event_enabled).and_return false
      allow(Flipper).to receive(:enabled?).with(:validate_saved_claims_with_json_schemer).and_return true

      allow(IncomeAndAssets::SavedClaim).to receive(:find_by).and_return(claim)
      allow(claim).to receive_messages(to_pdf: pdf_path, persistent_attachments: [])

      allow(BenefitsIntake::Service).to receive(:new).and_return(service)
      allow(service).to receive(:uuid)
      allow(service).to receive(:request_upload)
      allow(service).to receive_messages(location:, perform_upload: response)
      allow(response).to receive(:success?).and_return true

      allow(IncomeAndAssets::Monitor).to receive(:new).and_return(monitor)
    end

    it 'submits the saved claim successfully' do
      expect(UserAccount).to receive(:find_by).and_return(user_account)
      expect(IncomeAndAssets::SavedClaim).to receive(:find_by).and_return(claim)

      expect(Lighthouse::Submission).to receive(:create)
      expect(Lighthouse::SubmissionAttempt).to receive(:create)
      expect(Datadog::Tracing).to receive(:active_trace)

      stamper = IncomeAndAssets::PDFStamper.new([])
      expect(IncomeAndAssets::PDFStamper).to receive(:new).with(:income_and_assets_generated_claim).and_return(stamper)
      expect(stamper).to receive(:run).and_return(pdf_path)
      expect(service).to receive(:valid_document?).with(document: pdf_path).and_return(pdf_path)

      expect(service).to receive(:perform_upload).with(
        upload_url: 'test_location', document: pdf_path, metadata: generated_metadata.to_json, attachments: []
      )
      expect(job).to receive(:cleanup_file_paths)

      job.perform(claim.id, user_account.id)
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
        config = { claim_class: 'IncomeAndAssets::SavedClaim' }
        msg = { 'args' => [claim.id, config], 'class' => 'IncomeAndAssets::BenefitsIntake::SubmitClaimJob', 'error_message' => 'An error occurred', 'queue' => 'low' }
        IncomeAndAssets::BenefitsIntake::SubmitClaimJob.within_sidekiq_retries_exhausted_block(msg) do
          expect(IncomeAndAssets::SavedClaim).to receive(:find_by).with(id: claim.id).and_return(claim)

          expect(monitor).to receive(:track_submission_exhaustion).with(msg, claim)
        end
      end
    end
  end

  # Rspec.describe
end
