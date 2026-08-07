# frozen_string_literal: true

require 'rails_helper'
require 'dependents_benefits/sidekiq/benefits_intake_job'

RSpec.describe DependentsBenefits::Sidekiq::BenefitsIntakeJob, type: :job do
  let(:job) { described_class.new }
  let(:stamper) { instance_double(DependentsBenefits::PdfStamper) }
  let(:lighthouse_mock) do
    double(:lighthouse_service, uuid: 'uuid', location: 'https://mock.va.gov/upload',
                                request_upload: ['https://mock.va.gov/upload', 'uuid'],
                                perform_upload: OpenStruct.new(success?: true, data: {}),
                                valid_document?: true)
  end
  let(:parent_claim) { create(:dependents_claim) }
  let(:successful_response) { DependentsBenefits::ServiceResponse.new(status: true) }
  let(:failure_response) { DependentsBenefits::ServiceResponse.new(status: false, error: StandardError.new('TEST')) }
  let(:user) { create(:evss_user) }
  let(:user_data) { DependentsBenefits::UserData.new(user, parent_claim.parsed_form).get_user_json }
  let(:claim_processor) { double('DependentsBenefits::ClaimProcessor') }
  let(:claim686c) { create(:add_remove_dependents_claim) }
  let(:claim674) { create(:student_claim) }
  let(:monitor) { DependentsBenefits::Monitor.new }
  let(:email) { DependentsBenefits::NotificationEmail.new(parent_claim.id) }

  let!(:parent_group) { create(:parent_claim_group, parent_claim:, user_data:) }

  before do
    allow(DependentsBenefits::PdfFill::Filler).to receive(:fill_form).and_return('tmp/pdfs/mock_form_final.pdf')
    allow(DependentsBenefits::PdfStamper).to receive(:new).and_return(stamper)
    allow(BenefitsIntake::Service).to receive(:new).and_return(lighthouse_mock)
    allow(DependentsBenefits::ClaimProcessor).to receive(:new).and_return(claim_processor)
    allow(DependentsBenefits::Monitor).to receive(:new).and_return(monitor)
    allow(DependentsBenefits::NotificationEmail).to receive(:new).and_return(email)
    allow(Flipper).to receive(:enabled?).with(:enable_686_674_benefits_intake_dpdf).and_return(false)
    allow(job).to receive(:collect_child_claims).and_return([claim686c, claim674])
  end

  describe '#perform' do
    it 'succeeds' do
      expect(job).to receive(:submit_claims_to_service).and_return successful_response
      expect(job).to receive(:handle_job_success)

      job.perform(parent_claim.id)
    end

    context 'with error handling' do
      it 'handles a failure response' do
        expect(job).to receive(:submit_claims_to_service).and_return failure_response
        expect(job).to receive(:permanent_failure?).and_return false
        expect(monitor).to receive(:track_error_event)

        expect do
          job.perform(parent_claim.id)
        end.to raise_error DependentsBenefits::Sidekiq::DependentSubmissionError, 'TEST'
      end
    end
  end

  describe '#submit_claims_to_service' do
    it 'submits the claim successfully' do
      expect(stamper).to receive(:run).at_least(:once)
      expect(job).to receive(:handle_job_success)
      expect(job).to receive(:cleanup_file_paths)

      job.perform(parent_claim.id)
    end

    context 'with error handling' do
      it 'handles a failure response' do
        expect(job).to receive(:generate_claim_pdfs).and_raise StandardError, 'TEST'
        expect(job).to receive(:permanent_failure?).and_return false
        expect(monitor).to receive(:track_error_event)

        expect do
          job.perform(parent_claim.id)
        end.to raise_error DependentsBenefits::Sidekiq::DependentSubmissionError, 'TEST'
      end
    end

    context 'with the digital pdf flag enabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:enable_686_674_benefits_intake_dpdf).and_return(true)
      end

      it 'call to_dpdf and does not apply any stamps' do
        expect(DependentsBenefits::PdfStamper).to receive(:new).with([]).and_return(stamper)
        expect(stamper).to receive(:run).at_least(:once)
        expect(job).to receive(:handle_job_success)
        expect(job).to receive(:cleanup_file_paths)
        expect(claim686c).to receive(:to_dpdf)
        expect(claim674).to receive(:to_dpdf)

        job.perform(parent_claim.id)
      end
    end
  end

  describe '#handle_permanent_failure' do
    let(:error) { StandardError.new('TEST') }

    it 'propagates the failure and sends email' do
      expect(claim_processor).to receive(:handle_permanent_failure)
      expect(job).to receive(:mark_parent_group_failed)
      expect(monitor).to receive(:log_silent_failure_avoided)
      expect(email).to receive(:send_error_notification)

      job.send(:handle_permanent_failure, error)
    end

    it 'send silent failure on error' do
      expect(claim_processor).to receive(:handle_permanent_failure).and_raise error
      expect(job).to receive(:mark_parent_group_failed)
      expect(monitor).to receive(:log_silent_failure).with(hash_including(error:))

      job.send(:handle_permanent_failure, ArgumentError)
    end
  end

  describe '#handle_job_success' do
    let(:error) { StandardError.new('TEST') }

    it 'marks group processing' do
      expect(job).to receive(:mark_parent_group_processing)
      expect(monitor).to receive(:track_info_event)

      job.send(:handle_job_success)
    end

    it 'records an error' do
      expect(job).to receive(:mark_parent_group_processing).and_raise error
      expect(monitor).to receive(:track_error_event).with('Error handling job success', hash_including(error:))

      job.send(:handle_job_success)
    end
  end

  describe 'sidekiq_retries_exhausted callback' do
    it 'calls handle_permanent_failure' do
      msg = { 'args' => [parent_claim.id, 'proc_id'], 'class' => job.class.name }
      exception = StandardError.new('Service failed')

      expect_any_instance_of(described_class).to receive(:handle_permanent_failure).with(exception)

      described_class.sidekiq_retries_exhausted_block.call(msg, exception)
    end
  end
end
