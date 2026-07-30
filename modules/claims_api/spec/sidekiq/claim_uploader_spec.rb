# frozen_string_literal: true

require 'rails_helper'
require 'bd/bd'

RSpec.describe ClaimsApi::ClaimUploader, type: :job do
  subject { described_class }

  before do
    Sidekiq::Job.clear_all
    allow(Flipper).to receive(:enabled?).with(:claims_load_testing).and_return false
  end

  let(:user) { create(:user, :loa3) }
  let(:auth_headers) do
    EVSS::DisabilityCompensationAuthHeaders.new(user).add_headers(EVSS::AuthHeaders.new(user).to_h)
  end

  let(:supporting_document) do
    claim = create(:auto_established_claim_with_supporting_documents, :established)
    supporting_document = claim.supporting_documents[0]
    supporting_document.set_file_data!(
      Rack::Test::UploadedFile.new(
        Rails.root.join(*'/modules/claims_api/spec/fixtures/extras.pdf'.split('/')).to_s
      ),
      'docType',
      'description'
    )
    supporting_document.save!
    supporting_document
  end

  let(:supporting_document_failed_submission) do
    supporting_document = create(:supporting_document)
    supporting_document.set_file_data!(
      Rack::Test::UploadedFile.new(
        Rails.root.join(*'/modules/claims_api/spec/fixtures/extras.pdf'.split('/')).to_s
      ),
      'docType',
      'description'
    )
    supporting_document.save!
    supporting_document
  end

  let(:auto_claim) do
    claim = create(:auto_established_claim, evss_id: '12345', status: 'pending')
    claim.auth_headers['va_eauth_pid'] = '600043284'
    claim.set_file_data!(
      Rack::Test::UploadedFile.new(
        Rails.root.join(*'/modules/claims_api/spec/fixtures/extras.pdf'.split('/')).to_s
      ),
      'docType',
      'description'
    )
    claim.save!
    claim
  end

  let(:pending_auto_claim) do
    claim = create(:auto_established_claim, evss_id: nil, status: 'pending')
    claim.set_file_data!(
      Rack::Test::UploadedFile.new(
        Rails.root.join(*'/modules/claims_api/spec/fixtures/extras.pdf'.split('/')).to_s
      ),
      'docType',
      'description'
    )
    claim.save!
    claim
  end

  let(:errored_auto_claim) do
    claim = create(:auto_established_claim, evss_id: nil, status: 'errored')
    claim.set_file_data!(
      Rack::Test::UploadedFile.new(
        Rails.root.join(*'/modules/claims_api/spec/fixtures/extras.pdf'.split('/')).to_s
      ),
      'docType',
      'description'
    )
    claim.save!
    claim
  end

  let(:original_filename) { 'extras' }

  it 'submits successfully' do
    expect do
      subject.perform_async(supporting_document.id)
    end.to change(subject.jobs, :size).by(1)
  end

  it 'submits successfully with BD' do
    expect_any_instance_of(
      ClaimsApi::DisabilityCompensation::DisabilityDocumentService
    ).to receive(:create_upload).and_return true

    subject.new.perform(supporting_document.id, 'document')
    supporting_document.reload
    expect(auto_claim.uploader.blank?).to be(false)
  end

  it 'raises when evss_id is nil so Sidekiq retries automatically' do
    expect do
      subject.new.perform(errored_auto_claim.id, 'claim')
    end.to raise_error(RuntimeError, /evss_id not yet available/)

    expect(subject.jobs).to be_empty
  end

  describe 'BD document type' do
    it 'is a 526' do
      tf = Tempfile.new(['pdf_path', '.pdf'], binmode: true)
      allow(Tempfile).to receive(:new).and_return tf

      args = { claim: auto_claim, doc_type: 'L122', original_filename: 'extras.pdf', pdf_path: tf.path,
               version: 'v1' }
      expect_any_instance_of(
        ClaimsApi::DisabilityCompensation::DisabilityDocumentService
      ).to receive(:create_upload).with(args).and_return true
      subject.new.perform(auto_claim.id, 'claim')
    end

    it 'is an attachment' do
      tf = Tempfile.new(['pdf_path', '.pdf'], binmode: true)
      allow(Tempfile).to receive(:new).and_return tf

      args = { claim: supporting_document.auto_established_claim, doc_type: 'L023',
               original_filename: 'extras.pdf', pdf_path: tf.path, version: 'v1' }
      expect_any_instance_of(
        ClaimsApi::DisabilityCompensation::DisabilityDocumentService
      ).to receive(:create_upload).with(args).and_return true
      subject.new.perform(supporting_document.id, 'document')
    end

    it 'sends participantId instead of fileNumber in the upload body' do
      upload_body = nil
      allow_any_instance_of(ClaimsApi::BD).to receive(:upload_document) do |_instance, **args|
        upload_body = args[:body]
        { data: { success: true, requestId: 99 } }
      end

      subject.new.perform(auto_claim.id, 'claim')

      params_json = upload_body[:parameters].read
      data = JSON.parse(params_json)['data']
      expect(data['participantId']).to eq('600043284')
      expect(data).not_to have_key('fileNumber')
    end

    it 'sends the v1-specific systemName in the upload body' do
      upload_body = nil
      allow_any_instance_of(ClaimsApi::BD).to receive(:upload_document) do |_instance, **args|
        upload_body = args[:body]
        { data: { success: true, requestId: 99 } }
      end

      subject.new.perform(auto_claim.id, 'claim')

      params_json = upload_body[:parameters].read
      data = JSON.parse(params_json)['data']
      expect(data['systemName']).to eq('Lighthouse')
    end

    it 'is an attachment resulting in error' do
      tf = Tempfile.new(['pdf_path', '.pdf'], binmode: true)
      allow(Tempfile).to receive(:new).and_return tf

      body = {
        messages: [
          { key: '',
            severity: 'ERROR',
            text: 'Error calling external service to upload claim document.' }
        ]
      }
      args = { claim: supporting_document.auto_established_claim, doc_type: 'L023',
               original_filename: 'extras.pdf', pdf_path: tf.path, version: 'v1' }
      allow_any_instance_of(
        ClaimsApi::DisabilityCompensation::DisabilityDocumentService
      ).to(
        receive(:create_upload).with(args).and_raise(Common::Exceptions::BackendServiceException.new('', {}, 500, body))
      )
      expect do
        subject.new.perform(supporting_document.id, 'document')
      end.to raise_error(Common::Exceptions::BackendServiceException)
    end
  end

  describe 'when an errored job has exhausted its retries' do
    it 'logs to the ClaimsApi Logger' do
      error_msg = 'An error occurred from the Claim Uploader Job'
      msg = { 'args' => [auto_claim.id],
              'class' => subject,
              'error_message' => error_msg }

      described_class.within_sidekiq_retries_exhausted_block(msg) do
        expect(ClaimsApi::Logger).to receive(:log).with(
          'claims_api_retries_exhausted',
          record_id: auto_claim.id,
          message: "Job retries exhausted for #{subject}",
          error: error_msg
        )
      end
    end
  end
end
