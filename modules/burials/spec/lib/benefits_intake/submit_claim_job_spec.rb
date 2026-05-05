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

  describe '#perform' do
    let(:response) { double('response') }
    let(:pdf_path) { 'random/path/to/pdf' }
    let(:location) { 'test_location' }

    before do
      allow(Flipper).to receive(:enabled?).with(:burial_kafka_event_enabled).and_return false
      allow(Flipper).to receive(:enabled?).with(:validate_saved_claims_with_json_schemer).and_return true

      allow(Burials::SavedClaim).to receive(:find_by).and_return(claim)
      allow(claim).to receive_messages(to_pdf: pdf_path, persistent_attachments: [])

      allow(BenefitsIntake::Service).to receive(:new).and_return(service)
      allow(service).to receive(:uuid)
      allow(service).to receive(:request_upload)
      allow(service).to receive_messages(location:, perform_upload: response)
      allow(response).to receive(:success?).and_return true

      allow(Burials::Monitor).to receive(:new).and_return(monitor)
    end

    it 'submits the saved claim successfully' do
      expect(UserAccount).to receive(:find_by).and_return(user_account)
      expect(Burials::SavedClaim).to receive(:find_by).and_return(claim)

      expect(Lighthouse::Submission).to receive(:create)
      expect(Lighthouse::SubmissionAttempt).to receive(:create)
      expect(Datadog::Tracing).to receive(:active_trace)

      stamper = Burials::PDFStamper.new([])
      expect(Burials::PDFStamper).to receive(:new).with(:burials_generated_claim).and_return(stamper)
      expect(stamper).to receive(:run).and_return(pdf_path)
      expect(service).to receive(:valid_document?).with(document: pdf_path).and_return(pdf_path)

      expect(service).to receive(:perform_upload).with(
        upload_url: 'test_location', document: pdf_path, metadata: anything, attachments: []
      )

      expect(job).to receive(:send_claim_email)
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
      allow(Burials::Monitor).to receive(:new).and_return(monitor)
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
          expect(Burials::SavedClaim).to receive(:find_by).with(id: claim.id).and_return(claim)

          expect(monitor).to receive(:track_submission_exhaustion).with(msg, claim)
        end
      end
    end
  end

  # Rspec.describe
end
