# frozen_string_literal: true

require 'rails_helper'

require 'claims_evidence_api/uploader'
require 'dependents_benefits/claim_processor'
require 'dependents_benefits/sidekiq/claims_evidence_form_job'
require 'dependents_benefits/pdf_stamper'
require 'dependents_benefits/user_data'

RSpec.describe DependentsBenefits::Sidekiq::ClaimsEvidenceFormJob, type: :job do
  before do
    allow(DependentsBenefits::PdfFill::Filler).to receive(:fill_form).and_return('tmp/pdfs/mock_form_final.pdf')
    allow(Flipper).to receive(:enabled?).with(:enable_686_674_digital_pdf).and_return(false)
  end

  let(:user) { create(:evss_user) }
  let(:parent_claim) { create(:dependents_claim, :with_attachments) }
  let(:saved_claim) { create(:student_claim) }
  let(:user_data) { DependentsBenefits::UserData.new(user, saved_claim.parsed_form).get_user_json }
  let!(:parent_group) { create(:parent_claim_group, parent_claim:, user_data:) }
  let!(:current_group) { create(:saved_claim_group, saved_claim:, parent_claim:) }
  let(:job) { described_class.new }
  let(:claims_evidence_uploader) { instance_double(ClaimsEvidenceApi::Uploader) }
  let(:stamper) { instance_double(DependentsBenefits::PdfStamper) }

  describe '#submit_claims_to_service' do
    let(:child_claims) { [saved_claim] }

    before do
      allow(job).to receive(:submit_claim_to_service).with(saved_claim).and_return(
        DependentsBenefits::ServiceResponse.new(status: true)
      )
      allow(job).to receive(:claims_evidence_uploader).with(parent_claim).and_return(claims_evidence_uploader)
      allow(job).to receive_messages(child_claims:, parent_claim:)

      allow(DependentsBenefits::PdfStamper).to receive(:new).and_return(stamper)
    end

    it 'submits each child claim and attachments to the service' do
      expect(job).to receive(:submit_claim_to_service).with(saved_claim)

      expect(stamper).to receive(:run).twice
      expect(claims_evidence_uploader).to receive(:upload_evidence).twice

      response = job.send(:submit_claims_to_service)
      expect(response).to be_a(DependentsBenefits::ServiceResponse)
      expect(response.success?).to be true
    end

    it 'raises DependentSubmissionError on failure' do
      allow(job).to receive(:submit_claim_to_service).with(saved_claim).and_return(
        DependentsBenefits::ServiceResponse.new(status: false, error: 'Submission failed')
      )
      expect do
        job.send(:submit_claims_to_service)
      end.to raise_error(DependentsBenefits::Sidekiq::DependentSubmissionError, 'Submission failed')
    end
  end

  describe '#submit_to_claims_evidence_api' do
    before do
      allow(job).to receive(:claims_evidence_uploader).with(saved_claim).and_return(claims_evidence_uploader)
      allow(claims_evidence_uploader).to receive(:upload_evidence).and_return(true)
      allow(saved_claim).to receive(:to_pdf).and_return('tmp/pdfs/mock_form_final.pdf')
    end

    it 'processes PDF and uploads evidence' do
      stamp_set = DependentsBenefits::PdfStamper.form_stamp_set(saved_claim.form_id)
      expect(DependentsBenefits::PdfStamper).to receive(:new).with(stamp_set).and_return stamper
      expect(stamper).to receive(:run).and_return 'file_path'
      expect(claims_evidence_uploader).to receive(:upload_evidence).with(
        saved_claim.id,
        file_path: 'file_path',
        form_id: saved_claim.form_id,
        doctype: saved_claim.document_type
      )

      job.send(:submit_to_claims_evidence_api, saved_claim)
    end

    it 'raises exception when error occurs' do
      error = StandardError.new('Test error')
      expect(DependentsBenefits::PdfStamper).to receive(:new).and_return(stamper)
      expect(stamper).to receive(:run).and_raise(error)

      expect { job.send(:submit_to_claims_evidence_api, saved_claim) }.to raise_error(StandardError, 'Test error')
    end

    context 'with the digital pdf feature flag on' do
      before do
        allow(Flipper).to receive(:enabled?).with(:enable_686_674_digital_pdf).and_return(true)
      end

      it 'does not call the stamper' do
        stamp_set = DependentsBenefits::PdfStamper.form_stamp_set(saved_claim.form_id)
        expect(DependentsBenefits::PdfStamper).to receive(:new).with(stamp_set).and_return stamper
        expect(stamper).not_to receive(:run)
        expect(claims_evidence_uploader).to receive(:upload_evidence).with(
          saved_claim.id,
          file_path: String,
          form_id: saved_claim.form_id,
          doctype: saved_claim.document_type
        )

        job.send(:submit_to_claims_evidence_api, saved_claim)
      end
    end
  end

  describe '#submit_686c_form' do
    before do
      allow(job).to receive(:submit_to_claims_evidence_api).with(saved_claim)
    end

    it 'calls submit_to_claims_evidence_api with the claim' do
      expect(job).to receive(:submit_to_claims_evidence_api).with(saved_claim)
      job.send(:submit_686c_form, saved_claim)
    end
  end

  describe '#submit_674_form' do
    before do
      allow(job).to receive(:submit_to_claims_evidence_api).with(saved_claim)
    end

    it 'calls submit_to_claims_evidence_api with the claim' do
      expect(job).to receive(:submit_to_claims_evidence_api).with(saved_claim)
      job.send(:submit_674_form, saved_claim)
    end
  end

  describe '#find_or_create_form_submission' do
    it 'creates a ClaimsEvidenceApi::Submission record' do
      expect(ClaimsEvidenceApi::Submission).to receive(:find_or_create_by).with(
        form_id: '21-674',
        saved_claim_id: saved_claim.id
      )
      job.send(:find_or_create_form_submission, saved_claim)
    end
  end

  describe '#create_form_submission_attempt' do
    let(:submission) { create(:claims_evidence_submission, saved_claim:, form_id: '21-674') }

    it 'creates a new ClaimsEvidenceApi::SubmissionAttempt' do
      expect do
        job.send(:create_form_submission_attempt, submission)
      end.to change(ClaimsEvidenceApi::SubmissionAttempt, :count).by(1)
    end
  end

  describe '#submission_previously_succeeded?' do
    let(:submission) { create(:claims_evidence_submission, saved_claim:, form_id: '21-674') }

    context 'when submission has an accepted attempt' do
      before do
        create(:claims_evidence_submission_attempt, submission:, status: 'accepted')
      end

      it 'returns true' do
        expect(job.send(:submission_previously_succeeded?, submission)).to be true
      end
    end

    context 'when submission has only failed attempts' do
      before do
        create(:claims_evidence_submission_attempt, submission:, status: 'failed')
      end

      it 'returns false' do
        expect(job.send(:submission_previously_succeeded?, submission)).to be false
      end
    end

    context 'when submission is nil' do
      it 'returns falsy value' do
        expect(job.send(:submission_previously_succeeded?, nil)).to be_falsy
      end
    end
  end

  describe '#mark_submission_succeeded' do
    let(:submission) { create(:claims_evidence_submission, saved_claim:, form_id: '21-674') }
    let(:submission_attempt) { create(:claims_evidence_submission_attempt, submission:, status: 'pending') }

    before do
      allow(job).to receive(:submission_attempt).and_return(submission_attempt)
    end

    it 'marks attempt as accepted' do
      expect { job.send(:mark_submission_attempt_succeeded, submission_attempt) }
        .to change { submission_attempt.reload.status }.from('pending').to('accepted')
    end
  end

  describe '#mark_submission_attempt_failed' do
    let(:submission) { create(:claims_evidence_submission, saved_claim:, form_id: '21-674') }
    let(:submission_attempt) { create(:claims_evidence_submission_attempt, submission:, status: 'pending') }
    let(:error) { StandardError.new('Test error') }

    it 'marks the submission attempt as failed' do
      expect { job.send(:mark_submission_attempt_failed, submission_attempt, error) }
        .to change { submission_attempt.reload.status }.from('pending').to('failed')
    end

    it 'records the error message' do
      job.send(:mark_submission_attempt_failed, submission_attempt, error)
      submission_attempt.reload

      expect(submission_attempt.error_message).to eq('Test error')
    end

    it 'handles nil submission_attempt gracefully' do
      expect { job.send(:mark_submission_attempt_failed, nil, error) }.not_to raise_error
    end
  end

  describe '#permanent_failure?' do
    context 'with nil error' do
      it 'returns false' do
        expect(job.send(:permanent_failure?, nil)).to be false
      end
    end

    context 'with non-VEFS error' do
      it 'returns false' do
        error = StandardError.new('Regular error')
        expect(job.send(:permanent_failure?, error)).to be false
      end
    end

    context 'with VEFS error' do
      let(:vefs_error) { ClaimsEvidenceApi::Exceptions::VefsError.new(ClaimsEvidenceApi::Exceptions::VefsError::INVALID_JWT) }

      it 'returns true for permanent error codes' do
        expect(job.send(:permanent_failure?, vefs_error)).to be true
      end

      it 'returns false for non-permanent error codes' do
        transient_error = ClaimsEvidenceApi::Exceptions::VefsError.new('TEMPORARY_FAILURE')
        expect(job.send(:permanent_failure?, transient_error)).to be false
      end
    end

    context 'with nested VEFS error' do
      let(:vefs_error) { ClaimsEvidenceApi::Exceptions::VefsError.new(ClaimsEvidenceApi::Exceptions::VefsError::UNAUTHORIZED) }
      let(:wrapper_error) do
        error = StandardError.new
        error.set_backtrace([])
        allow(error).to receive(:cause).and_return(vefs_error)
        error
      end

      it 'returns true for permanent error codes in cause' do
        expect(job.send(:permanent_failure?, wrapper_error)).to be true
      end
    end
  end

  describe '#claims_evidence_uploader' do
    it 'creates uploader with folder identifier' do
      expect(ClaimsEvidenceApi::Uploader).to receive(:new).with(saved_claim.folder_identifier)
      job.send(:claims_evidence_uploader, saved_claim)
    end
  end
end
