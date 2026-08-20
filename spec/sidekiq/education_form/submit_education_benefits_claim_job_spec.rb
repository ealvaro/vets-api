# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EducationForm::SubmitEducationBenefitsClaimJob, form: :education_benefits, type: :model do
  subject { described_class.new }

  let(:claim) { create(:va10278) }
  let(:form_pdf_path) { 'tmp/test-submit-education-benefits-claim-job.pdf' }
  let(:stub_service) { double('BenefitsIntake::Service') }
  let(:stub_monitor) { double('EducationBenefitsClaims::Monitor') }
  let(:generated_pdfs) { [] }

  before do
    # PDFStamper leaves its source behind and the stubbed intake service means the job
    # cannot clean up after itself; track both paths so the spec can
    allow_any_instance_of(PDFUtilities::PDFStamper).to receive(:run).and_wrap_original do |original, path, **kw|
      generated_pdfs << path
      original.call(path, **kw).tap { |stamped| generated_pdfs << stamped }
    end

    allow(BenefitsIntake::Service).to receive(:new).and_return(stub_service)
    allow(stub_service).to receive(:request_upload)
    allow(stub_service).to receive_messages(valid_document?: form_pdf_path, location: 'http://example.com/upload',
                                            uuid: 'acde070d-8c4c-4f0d-9d8a-162843c10333')
    allow(claim).to receive(:to_pdf).and_return(form_pdf_path)

    allow(EducationBenefitsClaims::Monitor).to receive(:new).and_return(stub_monitor)
    allow(stub_monitor).to receive(:track_submission_success)
    allow(stub_monitor).to receive(:track_submission_retry)
    allow(stub_monitor).to receive(:track_submission_begun)
    allow(stub_monitor).to receive(:track_submission_attempted)
  end

  after do
    generated_pdfs.each { |path| Common::FileHelpers.delete_file_if_exists(path) }
  end

  describe '#perform' do
    context 'with a missing claim' do
      it 'raises an error' do
        expect { subject.perform(123) }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context 'with an invalid form type' do
      let(:claim) { create(:va0803) }

      it 'raises an error' do
        expect { subject.perform(claim.id) }.to raise_error(EducationForm::SubmitEducationBenefitsClaimJob::EducationBenefitClaimIntakeError)
      end
    end

    context 'with a pending lighthouse submission' do
      before do
        create(:lighthouse_submission, :pending, saved_claim: claim)
      end

      it 'returns and does nothing' do
        expect(stub_service).not_to receive(:request_upload)
        subject.perform(claim.id)
      end
    end

    context 'with an invalid document' do
      before do
        allow(stub_service).to receive(:valid_document?).and_raise(BenefitsIntake::Service::InvalidDocumentError)
      end

      it 'returns and does nothing' do
        expect { subject.perform(claim.id) }.to raise_error(BenefitsIntake::Service::InvalidDocumentError)
      end
    end

    context 'with a failed upload' do
      before do
        allow(stub_service).to receive(:perform_upload).and_return(OpenStruct.new(success?: false,
                                                                                  to_s: 'error occurred'))
      end

      it 'returns and does nothing' do
        expect do
          subject.perform(claim.id)
        end.to raise_error(
          EducationForm::SubmitEducationBenefitsClaimJob::EducationBenefitClaimIntakeError, 'error occurred'
        )
      end

      it 'marks the submission attempt as failed and calls the monitor' do
        expect(stub_monitor).to receive(:track_submission_retry)
        expect do
          subject.perform(claim.id)
        rescue
          # pass
        end.to change(Lighthouse::SubmissionAttempt, :count).by(1)

        expect(Lighthouse::SubmissionAttempt.first.status).to eq('failure')
      end
    end

    context 'with a successful upload' do
      before do
        allow(stub_service).to receive(:perform_upload).and_return(OpenStruct.new(success?: true))
      end

      it 'returns the upload uuid' do
        expect(subject.perform(claim.id)).to eq('acde070d-8c4c-4f0d-9d8a-162843c10333')
      end

      it 'marks the submission attempt as pending' do
        expect { subject.perform(claim.id) }.to change(Lighthouse::SubmissionAttempt, :count).by(1)
        expect(Lighthouse::SubmissionAttempt.first.status).to eq('pending')
      end

      it 'calls the monitor' do
        expect(stub_monitor).to receive(:track_submission_success)
        expect(stub_monitor).to receive(:track_submission_begun)
        expect(stub_monitor).to receive(:track_submission_attempted)
        subject.perform(claim.id)
      end
    end
  end

  describe 'supporting documents' do
    let(:captured) { {} }

    before do
      # echo the document back so the paths handed to the upload can be asserted on
      allow(stub_service).to receive(:valid_document?) { |document:| document }
      allow(stub_service).to receive(:perform_upload) do |**payload|
        captured[:payload] = payload
        captured[:attachments_on_disk] = payload[:attachments].select { |path| File.exist?(path) }
        OpenStruct.new(success?: true)
      end
    end

    shared_examples 'uploads supporting documents' do |form_id|
      context 'with supporting documents' do
        let!(:supporting_documents) do
          create_list(:claim_evidence, 2, saved_claim_id: claim.id, form_id:)
        end

        it 'passes a stamped document for each supporting document into the upload' do
          subject.perform(claim.id)

          attachments = captured[:payload][:attachments]
          expect(attachments.size).to eq(supporting_documents.size)
          expect(attachments.uniq.size).to eq(supporting_documents.size)
          expect(attachments).not_to include(captured[:payload][:document])
          expect(captured[:attachments_on_disk]).to match_array(attachments)
        end

        it 'reports the attachments to the monitor' do
          expect(stub_monitor).to receive(:track_submission_attempted) do |_claim, _service, _uuid, payload|
            expect(payload[:attachments].size).to eq(supporting_documents.size)
          end

          subject.perform(claim.id)
        end
      end

      context 'without supporting documents' do
        it 'uploads the form with no attachments' do
          subject.perform(claim.id)

          expect(captured[:payload][:attachments]).to eq([])
          expect(captured[:payload][:document]).to be_present
        end
      end
    end

    context 'with a 22-0810 claim' do
      let(:claim) { create(:va0810) }

      it_behaves_like 'uploads supporting documents', '22-0810'
    end

    context 'with a 22-10272 claim' do
      let(:claim) { create(:va10272) }

      it_behaves_like 'uploads supporting documents', '22-10272'
    end
  end

  describe 'exhaustion block' do
    context 'with no claim found' do
      it 'calls the monitor' do
        described_class.within_sidekiq_retries_exhausted_block({ 'args' => ['123'] }) do
          expect(stub_monitor).to receive(:track_submission_exhaustion).with(anything, nil)
        end
      end
    end

    context 'with claim found' do
      it 'calls the monitor' do
        described_class.within_sidekiq_retries_exhausted_block({ 'args' => [claim.id] }) do
          expect(stub_monitor).to receive(:track_submission_exhaustion).with(anything, claim)
        end
      end
    end
  end

  describe 'pdf stamp' do
    it 'generates the correct stamp data' do
      subject.claim = claim
      stamp_data = subject.send(:default_stamp_set)
      expect(stamp_data.first[:text]).to include('Signed electronically and submitted via VA.gov')
      expect(stamp_data.first[:text]).to include('Signee signed with an identity-verified account.')
      expect(stamp_data.first[:text_only]).to be(true)
    end
  end
end
