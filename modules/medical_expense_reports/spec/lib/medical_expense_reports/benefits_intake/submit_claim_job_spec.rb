# frozen_string_literal: true

require 'rails_helper'
require 'lighthouse/benefits_intake/service'
require 'medical_expense_reports/benefits_intake/submit_claim_job'
require 'medical_expense_reports/monitor'
require 'pdf_utilities/datestamp_pdf'

RSpec.describe MedicalExpenseReports::BenefitsIntake::SubmitClaimJob, :uploader_helpers do
  stub_virus_scan
  let(:job) { described_class.new }
  let(:claim) { create(:medical_expense_reports_claim) }
  let(:service) { double('service') }
  let(:monitor) { MedicalExpenseReports::Monitor.new }
  let(:user_account_uuid) { 123 }

  describe '#perform' do
    let(:response) { double('response') }
    let(:pdf_path) { 'random/path/to/pdf' }
    let(:location) { 'test_location' }
    let(:omit_esign_stamp) { true }
    let(:omit_footer) { true }
    let(:extras_redesign) { true }
    let(:current_loa) { 3 }
    let(:parsed_form) do
      {
        'veteranFullName' => { 'first' => 'John', 'last' => 'Doe' },
        'veteranSocialSecurityNumber' => '333224444',
        'claimantAddress' => { 'postalCode' => '22030' }
      }
    end

    before do
      job.instance_variable_set(:@claim, claim)
      allow(MedicalExpenseReports::SavedClaim).to receive(:find).and_return(claim)
      allow(claim).to receive(:to_pdf)
        .with(claim.id, { extras_redesign:, omit_esign_stamp:, omit_footer: }).and_return(pdf_path)
      allow(MedicalExpenseReports::PdfFill::Va21p8416).to receive(:stamp_submission_footer).and_return(pdf_path)
      allow(claim).to receive_messages(persistent_attachments: [], parsed_form:)

      job.instance_variable_set(:@intake_service, service)
      allow(BenefitsIntake::Service).to receive(:new).and_return(service)
      allow(service).to receive(:uuid)
      allow(service).to receive(:request_upload)
      allow(service).to receive_messages(location:, perform_upload: response)
      allow(response).to receive(:success?).and_return true

      job.instance_variable_set(:@monitor, monitor)

      # Deterministic feature-flag control: the form flag is on by default,
      # structured-data transmission off unless a specific example enables it.
      allow(Flipper).to receive(:enabled?).and_call_original
      allow(Flipper).to receive(:enabled?).with(:medical_expense_reports_form_enabled).and_return(true)
      allow(Flipper).to receive(:enabled?).with(:medical_expense_reports_structured_data_transmission).and_return(false)
    end

    context 'with medical_expense_reports_form_enabled flipper' do
      before do
        allow(UserAccount).to receive(:find).and_return(double('user_account'))
      end

      it 'processes claim when flipper is enabled' do
        allow(Flipper).to receive(:enabled?).with(:medical_expense_reports_form_enabled).and_return(true)
        allow(job).to receive(:process_document).and_return(pdf_path)

        expect(MedicalExpenseReports::SavedClaim).to receive(:find).and_return(claim)
        expect(claim).to receive(:to_pdf)
        expect(service).to receive(:perform_upload)
        expect(job).to receive(:cleanup_file_paths)

        result = job.perform(claim.id, user_account_uuid)
        expect(result).to eq(service.uuid)
      end

      it 'cleans up the intermediate PDFs generated before process_document' do
        raw_path = 'tmp/raw.pdf'
        stamped_path = 'tmp/stamped.pdf'
        form_path = 'tmp/form.pdf'
        allow(claim).to receive(:to_pdf).and_return(raw_path)
        allow(MedicalExpenseReports::PdfFill::Va21p8416).to receive(:stamp_submission_footer).and_return(stamped_path)
        allow(job).to receive(:process_document).and_return(form_path)
        allow(Common::FileHelpers).to receive(:delete_file_if_exists)

        job.perform(claim.id, user_account_uuid, current_loa)

        expect(Common::FileHelpers).to have_received(:delete_file_if_exists).with(raw_path)
        expect(Common::FileHelpers).to have_received(:delete_file_if_exists).with(stamped_path)
      end

      it 'returns early when flipper is disabled' do
        allow(Flipper).to receive(:enabled?).with(:medical_expense_reports_form_enabled).and_return(false)

        expect(MedicalExpenseReports::SavedClaim).not_to receive(:find)
        expect(claim).not_to receive(:to_pdf)
        expect(service).not_to receive(:perform_upload)

        result = job.perform(claim.id, user_account_uuid)
        expect(result).to be_nil
      end
    end

    it 'submits the saved claim successfully' do
      allow(job).to receive(:process_document).and_return(pdf_path)

      expect(claim).to receive(:to_pdf)
        .with(claim.id, { extras_redesign:, omit_esign_stamp:, omit_footer: }).and_return(pdf_path)
      expect(MedicalExpenseReports::PdfFill::Va21p8416).to receive(:stamp_submission_footer)
        .with(pdf_path, claim.created_at, current_loa).and_return(pdf_path)
      expect(Lighthouse::Submission).to receive(:create)
      expect(Lighthouse::SubmissionAttempt).to receive(:create)
      expect(Datadog::Tracing).to receive(:active_trace)
      expect(UserAccount).to receive(:find)

      expect(service).to receive(:perform_upload).with(
        upload_url: 'test_location', document: pdf_path, metadata: anything, attachments: []
      )
      expect(job).to receive(:cleanup_file_paths)

      job.perform(claim.id, :user_account_uuid, current_loa)
    end

    it 'is unable to find user_account' do
      expect(MedicalExpenseReports::SavedClaim).not_to receive(:find)
      expect(BenefitsIntake::Service).not_to receive(:new)
      expect(claim).not_to receive(:to_pdf)

      expect(job).to receive(:cleanup_file_paths)
      expect(monitor).to receive(:track_submission_retry)

      expect { job.perform(claim.id, :user_account_uuid) }.to raise_error(
        ActiveRecord::RecordNotFound,
        /Couldn't find UserAccount/
      )
    end

    it 'is unable to find saved_claim_id' do
      allow(MedicalExpenseReports::SavedClaim).to receive(:find).and_return(nil)

      expect(UserAccount).to receive(:find)

      expect(BenefitsIntake::Service).not_to receive(:new)
      expect(claim).not_to receive(:to_pdf)

      expect(job).to receive(:cleanup_file_paths)
      expect(monitor).to receive(:track_submission_retry)

      expect { job.perform(claim.id, :user_account_uuid) }.to raise_error(
        MedicalExpenseReports::BenefitsIntake::SubmitClaimJob::MedicalExpenseReportsBenefitIntakeError,
        "Unable to find MedicalExpenseReports::SavedClaim #{claim.id}"
      )
    end
    # perform
  end

  describe '#govcio_upload' do
    let(:ibm_service) { double('ibm_service') }
    let(:response) { double('response') }

    before do
      job.instance_variable_set(:@intake_service, service)
      allow(service).to receive(:uuid).and_return('test_guid')

      job.instance_variable_set(:@ibm_payload, { test: 'data' })

      allow(Ibm::Service).to receive(:new).and_return(ibm_service)
      allow(ibm_service).to receive(:upload_form).and_return(response)
      allow(response).to receive(:success?).and_return(true)
    end

    it 'uploads to IBM MMS when govcio flipper is enabled' do
      allow(Flipper)
        .to receive(:enabled?).with(:medical_expense_reports_structured_data_transmission).and_return(true)

      expect(Ibm::Service).to receive(:new)
      expect(ibm_service).to receive(:upload_form).with(form: { test: 'data' }.to_json, guid: 'test_guid')

      job.send(:govcio_upload)
    end

    it 'does not upload to IBM MMS when govcio flipper is disabled' do
      allow(Flipper)
        .to receive(:enabled?).with(:medical_expense_reports_structured_data_transmission).and_return(false)

      expect(Ibm::Service).not_to receive(:new)
      expect(ibm_service).not_to receive(:upload_form)

      job.send(:govcio_upload)
    end

    context 'when IBM upload raises an error' do
      it 'logs an error if IBM upload raises an error' do
        allow(Flipper)
          .to receive(:enabled?).with(:medical_expense_reports_structured_data_transmission).and_return(true)
        allow(ibm_service).to receive(:upload_form).and_raise(StandardError.new('IBM upload failed'))
        allow(service).to receive(:uuid).and_return('some-uuid')
        expect(Rails.logger).to receive(:error).with('IBM structured data transmission failed: IBM upload failed')

        job.send(:govcio_upload)
      end
    end
  end

  describe '#update_form_submission_attempt' do
    let(:user_account) { create(:user_account) }
    let(:claim) { create(:medical_expense_reports_claim, user_account:) }

    before do
      job.instance_variable_set(:@claim, claim)
      job.instance_variable_set(:@intake_service, service)
      allow(service).to receive(:uuid).and_return('11111111-1111-4111-8111-111111111111')
    end

    # MyVA builds submitted-form cards from FormSubmission/FormSubmissionAttempt records,
    # so this association must be created and tied to the user and benefits intake uuid.
    it 'creates a FormSubmission and attempt tied to the user and benefits intake uuid' do
      expect { job.send(:update_form_submission_attempt) }
        .to change(FormSubmission, :count).by(1)
        .and change(FormSubmissionAttempt, :count).by(1)

      submission = claim.form_submissions.last
      expect(submission.form_type).to eq(claim.form_id)
      expect(submission.user_account_id).to eq(user_account.id)
      expect(submission.latest_attempt.benefits_intake_uuid).to eq('11111111-1111-4111-8111-111111111111')
    end

    it 'updates the existing attempt on retry instead of creating a duplicate' do
      job.send(:update_form_submission_attempt)
      allow(service).to receive(:uuid).and_return('22222222-2222-4222-8222-222222222222')

      expect { job.send(:update_form_submission_attempt) }
        .to not_change(FormSubmission, :count)
        .and not_change(FormSubmissionAttempt, :count)

      expect(claim.form_submissions.last.latest_attempt.benefits_intake_uuid)
        .to eq('22222222-2222-4222-8222-222222222222')
    end
  end

  describe '#process_document' do
    let(:service) { double('service') }
    let(:pdf_path) { 'random/path/to/pdf' }
    let(:datestamp_pdf_double) { instance_double(PDFUtilities::DatestampPdf) }

    before do
      job.instance_variable_set(:@intake_service, service)
    end

    it 'returns a datestamp pdf path' do
      run_count = 0
      allow(PDFUtilities::DatestampPdf).to receive(:new).and_return(datestamp_pdf_double)
      allow(datestamp_pdf_double).to receive(:run) {
        run_count += 1
        pdf_path
      }
      allow(service).to receive(:valid_document?).and_return(pdf_path)
      allow(File).to receive(:exist?).with(pdf_path).and_return(true)
      new_path = job.send(:process_document, 'test/path')

      expect(new_path).to eq(pdf_path)
      expect(run_count).to eq(2)
    end
    # process_document
  end

  describe '#cleanup_file_paths' do
    before do
      job.instance_variable_set(:@form_path, 'path/file.pdf')
      job.instance_variable_set(:@attachment_paths, '/invalid_path/should_be_an_array.failure')

      job.instance_variable_set(:@monitor, monitor)
      allow(monitor).to receive(:track_file_cleanup_error)
    end

    it 'errors and logs but does not reraise' do
      expect(monitor).to receive(:track_file_cleanup_error)
      job.send(:cleanup_file_paths)
    end
  end

  describe '#footer_loa' do
    it 'returns the provided positive LOA' do
      job.instance_variable_set(:@current_loa, 3)
      job.instance_variable_set(:@user_account_uuid, 'uuid')
      expect(job.send(:footer_loa)).to eq(3)
    end

    it 'falls back to LOA 1 for an authenticated submitter whose LOA is missing (deploy replay)' do
      job.instance_variable_set(:@current_loa, nil)
      job.instance_variable_set(:@user_account_uuid, 'uuid')
      expect(job.send(:footer_loa)).to eq(1)
    end

    it 'returns nil for an unauthenticated submitter' do
      job.instance_variable_set(:@current_loa, nil)
      job.instance_variable_set(:@user_account_uuid, nil)
      expect(job.send(:footer_loa)).to be_nil
    end
  end

  describe '#send_submitted_email' do
    let(:monitor_error) { create(:monitor_error) }
    let(:notification) { double('notification') }

    before do
      job.instance_variable_set(:@claim, claim)

      allow(MedicalExpenseReports::NotificationEmail).to receive(:new).and_return(notification)
      allow(notification).to receive(:deliver).and_raise(monitor_error)

      job.instance_variable_set(:@monitor, monitor)
      allow(monitor).to receive(:track_send_email_failure)
    end

    it 'errors and logs but does not reraise' do
      expect(MedicalExpenseReports::NotificationEmail).to receive(:new).with(claim.id)
      expect(notification).to receive(:deliver).with(:submitted)
      expect(monitor).to receive(:track_send_email_failure)
      job.send(:send_submitted_email)
    end
  end

  describe 'sidekiq_retries_exhausted block' do
    let(:exhaustion_msg) do
      { 'args' => [], 'class' => 'MedicalExpenseReports::BenefitsIntake::SubmitClaimJob',
        'error_message' => 'An error occurred', 'queue' => 'low' }
    end

    before do
      allow(MedicalExpenseReports::Monitor).to receive(:new).and_return(monitor)
    end

    context 'when retries are exhausted' do
      it 'logs a distrinct error when no claim_id provided' do
        MedicalExpenseReports::BenefitsIntake::SubmitClaimJob.within_sidekiq_retries_exhausted_block do
          expect(monitor).to receive(:track_submission_exhaustion).with(exhaustion_msg, nil)
        end
      end

      it 'logs a distrinct error when only claim_id provided' do
        MedicalExpenseReports::BenefitsIntake::SubmitClaimJob
          .within_sidekiq_retries_exhausted_block({ 'args' => [claim.id] }) do
          allow(MedicalExpenseReports::SavedClaim).to receive(:find).and_return(claim)
          expect(MedicalExpenseReports::SavedClaim).to receive(:find).with(claim.id)

          exhaustion_msg['args'] = [claim.id]

          expect(monitor).to receive(:track_submission_exhaustion).with(exhaustion_msg, claim)
        end
      end

      it 'logs a distrinct error when claim_id and user_account_uuid provided' do
        MedicalExpenseReports::BenefitsIntake::SubmitClaimJob
          .within_sidekiq_retries_exhausted_block({ 'args' => [claim.id, 2] }) do
          allow(MedicalExpenseReports::SavedClaim).to receive(:find).and_return(claim)
          expect(MedicalExpenseReports::SavedClaim).to receive(:find).with(claim.id)

          exhaustion_msg['args'] = [claim.id, 2]

          expect(monitor).to receive(:track_submission_exhaustion).with(exhaustion_msg, claim)
        end
      end

      it 'logs a distrinct error when claim is not found' do
        MedicalExpenseReports::BenefitsIntake::SubmitClaimJob
          .within_sidekiq_retries_exhausted_block({ 'args' => [claim.id - 1, 2] }) do
          expect(MedicalExpenseReports::SavedClaim).to receive(:find).with(claim.id - 1)

          exhaustion_msg['args'] = [claim.id - 1, 2]

          expect(monitor).to receive(:track_submission_exhaustion).with(exhaustion_msg, nil)
        end
      end
    end
  end

  # Rspec.describe
end
