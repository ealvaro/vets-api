# frozen_string_literal: true

require 'rails_helper'
require 'bpds/service'
require 'bpds/monitor'
require 'bpds/submission'
require 'bpds/submission_attempt'
require 'bpds/sidekiq/submit_to_bpds_job'

RSpec.describe BPDS::Sidekiq::SubmitToBPDSJob, type: :job do
  let(:claim) { create(:pensions_saved_claim) }
  let(:participant_id) { '600061742' }
  let(:file_number) { '123123123' }
  let(:encrypted_payload) { KmsEncrypted::Box.new.encrypt({ 'participant_id' => participant_id }.to_json) }
  let(:encrypted_payload_file_number) { KmsEncrypted::Box.new.encrypt({ 'file_number' => file_number }.to_json) }
  let(:bpds_submission) { create(:bpds_submission, saved_claim: claim) }
  let(:bpds_submission_attempt) { double(BPDS::SubmissionAttempt) }
  let(:monitor) { double(BPDS::Monitor) }
  let(:service) { double(BPDS::Service) }
  let(:response) { { 'uuid' => '12345' } }

  before do
    allow(SavedClaim).to receive(:find).with(claim.id).and_return(claim)
    allow(BPDS::Submission).to receive(:find_or_create_by).and_return(bpds_submission)
    # rubocop:disable RSpec/MessageChain
    allow(bpds_submission).to receive_message_chain(:submission_attempts, :create).and_return(bpds_submission_attempt)
    # rubocop:enable RSpec/MessageChain
    allow(BPDS::Monitor).to receive(:new).and_return(monitor)
    allow(monitor).to receive(:track_submit_success)
    allow(monitor).to receive(:track_submit_failure)
    allow(monitor).to receive(:track_formatter_load_failure)
    allow(BPDS::Service).to receive(:new).and_return(service)
    allow(service).to receive(:submit_json).and_return(response)
    allow(Flipper).to receive(:enabled?).with(:bpds_service_enabled).and_return(true)
  end

  describe '#perform' do
    context 'when the feature flag is disabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:bpds_service_enabled).and_return(false)
      end

      it 'does not perform the job' do
        expect(described_class.new.perform(claim.id, encrypted_payload)).to be_nil
        expect(service).not_to have_received(:submit_json)
      end
    end

    context 'when the submission is successful' do
      context 'and participant_id is provided' do
        it 'submits the BPDS submission and creates a successful attempt' do
          described_class.new.perform(claim.id, encrypted_payload)

          identifiers = { 'participant_id' => participant_id }
          expect(service).to have_received(:submit_json).with(claim.parsed_form, claim.form_id, identifiers,
                                                              attachments: nil)
          expect(bpds_submission.submission_attempts).to have_received(:create).with(
            status: 'submitted',
            response: response.to_json,
            bpds_id: response['uuid']
          )
          expect(monitor).to have_received(:track_submit_success).with(claim.id, claim.form_id, response['uuid'])
        end
      end

      context 'and file_number is provided' do
        it 'submits the BPDS submission and creates a successful attempt' do
          described_class.new.perform(claim.id, encrypted_payload_file_number)

          identifiers = { 'file_number' => file_number }
          expect(service).to have_received(:submit_json).with(claim.parsed_form, claim.form_id, identifiers,
                                                              attachments: nil)
          expect(bpds_submission.submission_attempts).to have_received(:create).with(
            status: 'submitted',
            response: response.to_json,
            bpds_id: response['uuid']
          )
          expect(monitor).to have_received(:track_submit_success).with(claim.id, claim.form_id, response['uuid'])
        end
      end

      context 'and other identifiers are provided' do
        it 'submits the BPDS submission and creates a successful attempt' do
          identifiers = {
            file_number:,
            ssn: 'SSN',
            icn: 'ICN',
            foo_bar: 'snafu'
          }.stringify_keys
          encrypted = KmsEncrypted::Box.new.encrypt(identifiers.to_json)

          described_class.new.perform(claim.id, encrypted)

          expect(service).to have_received(:submit_json).with(claim.parsed_form, claim.form_id, identifiers,
                                                              attachments: nil)
          expect(bpds_submission.submission_attempts).to have_received(:create).with(
            status: 'submitted',
            response: response.to_json,
            bpds_id: response['uuid']
          )
          expect(monitor).to have_received(:track_submit_success).with(claim.id, claim.form_id, response['uuid'])
        end
      end
    end

    context 'when the claim has already been submitted' do
      before do
        allow(bpds_submission).to receive(:latest_status).and_return('submitted')
        allow(Rails.logger).to receive(:info)
      end

      it 'logs that the claim has already been submitted' do
        described_class.new.perform(claim.id, encrypted_payload)

        expect(Rails.logger).to have_received(:info).with(
          "Saved Claim #:#{claim.id} has already been submitted to BPDS"
        )
      end
    end

    context 'when the submission fails' do
      let(:error) { StandardError.new('Submission failed') }

      before do
        allow(service).to receive(:submit_json).and_raise(error)
      end

      it 'creates a failure attempt and raises the error' do
        expect do
          described_class.new.perform(claim.id, encrypted_payload)
        end.to raise_error(StandardError, 'Submission failed')

        expect(bpds_submission.submission_attempts).to have_received(:create).with(
          status: 'failure',
          error_message: 'Submission failed'
        )
        expect(monitor).to have_received(:track_submit_failure).with(claim.id, claim.form_id, error)
      end
    end

    context 'when a formatter is registered for the form' do
      let(:burial_claim) { create(:burials_saved_claim) }
      let(:formatter) { double('Formatter') }
      let(:formatted_data) { { 'formatted' => 'data' } }
      let(:formatter_class) do
        Class.new do
          def initialize(_parsed_form); end
          def format; end
        end
      end

      before do
        allow(SavedClaim).to receive(:find).with(burial_claim.id).and_return(burial_claim)
        allow(BPDS::Submission).to receive(:find_or_create_by).and_return(bpds_submission)
        stub_const('Burials::BPDS::Formatter', formatter_class)
        allow(formatter_class).to receive(:new).with(burial_claim.parsed_form).and_return(formatter)
        allow(formatter).to receive(:format).and_return(formatted_data)
      end

      it 'uses the formatter to format the claim data' do
        described_class.new.perform(burial_claim.id, encrypted_payload)

        expect(formatter_class).to have_received(:new).with(burial_claim.parsed_form)
        expect(formatter).to have_received(:format)

        identifiers = { 'participant_id' => participant_id }
        expect(service).to have_received(:submit_json).with(formatted_data, '21P-530EZ', identifiers, attachments: nil)
      end
    end

    context 'when the formatter provides attachments' do
      let(:sb_claim) { create(:pensions_saved_claim) }
      let(:formatter) { double('Formatter') }
      let(:formatted_data) { { 'formatted' => 'data' } }
      let(:attachments) { [{ 'index' => 1, 'name' => 'dd214.pdf' }] }
      let(:formatter_class) do
        Class.new do
          def initialize(_parsed_form); end
          def format; end
          def attachments; end
        end
      end

      before do
        allow(sb_claim).to receive(:form_id).and_return('21P-534EZ')
        allow(SavedClaim).to receive(:find).with(sb_claim.id).and_return(sb_claim)
        stub_const('SurvivorsBenefits::BPDS::Formatter', formatter_class)
        allow(formatter_class).to receive(:new).with(sb_claim.parsed_form).and_return(formatter)
        allow(formatter).to receive_messages(format: formatted_data, attachments:)
      end

      it 'passes the attachments through to the service' do
        described_class.new.perform(sb_claim.id, encrypted_payload)

        identifiers = { 'participant_id' => participant_id }
        expect(service).to have_received(:submit_json).with(formatted_data, '21P-534EZ', identifiers,
                                                            attachments:)
      end
    end

    context 'when a registered formatter cannot be resolved' do
      let(:burial_claim) { create(:burials_saved_claim) }

      before do
        allow(SavedClaim).to receive(:find).with(burial_claim.id).and_return(burial_claim)
        allow(BPDS::Submission).to receive(:find_or_create_by).and_return(bpds_submission)
        hide_const('Burials::BPDS::Formatter')
      end

      it 'falls back to the parsed_form and tracks the load failure' do
        described_class.new.perform(burial_claim.id, encrypted_payload)

        identifiers = { 'participant_id' => participant_id }
        expect(service).to have_received(:submit_json).with(burial_claim.parsed_form, '21P-530EZ', identifiers,
                                                            attachments: nil)
        expect(monitor).to have_received(:track_formatter_load_failure).with(
          burial_claim.id, '21P-530EZ', 'Burials::BPDS::Formatter', instance_of(NameError)
        )
      end
    end

    # NoMethodError is a subclass of NameError, so a rescue spanning the formatter's own work would
    # catch a bug inside the formatter and report it as a class that would not load - sending
    # whoever is on call after the wrong cause. The two must stay distinguishable, and only the
    # load failure falls back.
    context 'when a resolved formatter raises while building the payload' do
      let(:burial_claim) { create(:burials_saved_claim) }
      let(:formatter) { instance_double(Burials::BPDS::Formatter) }
      let(:error) { NoMethodError.new("undefined method 'foo' for nil") }

      before do
        allow(SavedClaim).to receive(:find).with(burial_claim.id).and_return(burial_claim)
        allow(BPDS::Submission).to receive(:find_or_create_by).and_return(bpds_submission)
        allow(monitor).to receive(:track_formatter_runtime_error)
        allow(Burials::BPDS::Formatter).to receive(:new).and_return(formatter)
        allow(formatter).to receive(:respond_to?).with(:attachments).and_return(false)
        allow(formatter).to receive(:format).and_raise(error)
      end

      it 'tracks a runtime error rather than a load failure' do
        expect do
          described_class.new.perform(burial_claim.id, encrypted_payload)
        end.to raise_error(NoMethodError)

        expect(monitor).to have_received(:track_formatter_runtime_error).with(
          burial_claim.id, '21P-530EZ', 'Burials::BPDS::Formatter', error
        )
        expect(monitor).not_to have_received(:track_formatter_load_failure)
      end

      # The point of re-raising: BPDS is never given a record built from raw parsed_form under a
      # submitted status, and a transient cause gets the same retries any other failure gets.
      it 'sends nothing to BPDS and records the attempt as a failure' do
        expect do
          described_class.new.perform(burial_claim.id, encrypted_payload)
        end.to raise_error(NoMethodError)

        expect(service).not_to have_received(:submit_json)
        expect(bpds_submission.submission_attempts).to have_received(:create).with(
          status: 'failure',
          error_message: error.message
        )
        expect(monitor).to have_received(:track_submit_failure).with(burial_claim.id, '21P-530EZ', error)
      end
    end

    context 'when no formatter is registered for the form' do
      it 'uses the parsed_form directly' do
        described_class.new.perform(claim.id, encrypted_payload)

        identifiers = { 'participant_id' => participant_id }
        expect(service).to have_received(:submit_json).with(claim.parsed_form, claim.form_id, identifiers,
                                                            attachments: nil)
      end
    end
  end

  describe '.sidekiq_retries_exhausted' do
    let(:msg) { { 'args' => [claim.id] } }
    let(:error) { StandardError.new('Retries exhausted') }

    before do
      allow(Rails.logger).to receive(:error)
      allow(SavedClaim).to receive(:find).with(claim.id).and_return(claim)
      allow(BPDS::Submission).to receive(:find_by).with(saved_claim: claim).and_return(bpds_submission)
    end

    it 'logs the error and creates a failed submission attempt' do
      described_class.sidekiq_retries_exhausted_block.call(msg, error)

      expect(Rails.logger).to have_received(:error).with(
        "SubmitToBPDSJob exhausted all retries for saved claim ID: #{claim.id}"
      )
      expect(bpds_submission.submission_attempts).to have_received(:create).with(
        status: 'failure',
        error_message: 'Retries exhausted'
      )
    end
  end
end
