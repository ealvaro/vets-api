# frozen_string_literal: true

require 'rails_helper'
require_relative '../rails_helper'
require_relative '../support/form_526_fixture_helper'
require 'claims_api/disability_compensation_benefits_documents_uploader'

RSpec.describe ClaimsApi::DisabilityCompensationBenefitsDocumentsUploader, type: :job do
  subject { described_class }

  let(:service) { described_class.new }
  let(:user) { create(:user, :loa3) }
  let(:auth_headers) do
    EVSS::DisabilityCompensationAuthHeaders.new(user).add_headers(EVSS::AuthHeaders.new(user).to_h)
  end
  let(:claim_date) { (Time.zone.today - 1.day).to_s }
  let(:anticipated_separation_date) { 2.days.from_now.strftime('%m-%d-%Y') }
  let(:form_data) do
    temp = Form526FixtureHelper.new.data
    attributes = temp['data']['attributes']
    attributes['claimDate'] = claim_date
    attributes['serviceInformation']['federalActivation']['anticipatedSeparationDate'] = anticipated_separation_date

    temp['data']['attributes']
  end
  let(:claim) do
    claim = create(:auto_established_claim, evss_id: '600966353')
    claim.auth_headers['va_eauth_pid'] = '600043201'
    claim.set_file_data!(
      Rack::Test::UploadedFile.new(
        Rails.root.join(*'/modules/claims_api/spec/fixtures/extras.pdf'.split('/')).to_s
      ),
      'docType',
      'description'
    )
    claim.status = ClaimsApi::AutoEstablishedClaim::PENDING
    claim.save!
    claim
  end

  before do
    Sidekiq::Job.clear_all
    stub_claims_api_auth_token
    allow(Flipper).to receive(:enabled?).with(:claims_load_testing).and_return false
  end

  context 'successful submission' do
    it 'successful submit should add the job' do
      expect do
        subject.perform_async(claim.id)
      end.to change(subject.jobs, :size).by(1)
    end

    it 'the claim should still be established on a successful BD submission' do
      VCR.use_cassette('claims_api/bd/upload') do
        expect(claim.status).to eq('pending') # where we start

        service.perform(claim.id)

        claim.reload
        expect(claim.status).to eq('established') # where we end
      end
    end

    it 'submits successfully with BD' do
      VCR.use_cassette('claims_api/bd/upload') do
        service.perform(claim.id)

        claim.reload
        expect(claim.uploader.blank?).to be(false)
      end
    end

    it 'clears stale evss_response from a prior failed attempt' do
      claim.update!(evss_response: ['Prior upload error'], status: ClaimsApi::AutoEstablishedClaim::ERRORED)

      VCR.use_cassette('claims_api/bd/upload') do
        service.perform(claim.id)
      end

      claim.reload
      expect(claim.status).to eq('established')
      expect(claim.evss_response).to be_nil
    end

    it 'sends participantId instead of fileNumber in the upload body' do
      # comment out stub_claims_api_auth_token to re-record the VCR cassette

      multipart_body = nil
      VCR.use_cassette('claims_api/bd/upload_with_pid') do
        service.perform(claim.id)

        # Grab the upload interaction before VCR ejects the cassette
        upload_request = VCR.current_cassette.serializable_hash['http_interactions'][1]
                            .dig('request', 'body') || {}
        multipart_body = upload_request['string'] || Base64.decode64(upload_request.fetch('base64_string'))
      end

      claim.reload
      expect(claim.status).to eq('established')

      # Parse the multipart request body to verify participantId is used
      body_str = multipart_body.encode('UTF-8', invalid: :replace, undef: :replace, replace: '')

      expect(body_str).to include('"participantId":"600043201"')
      expect(body_str).not_to include('fileNumber')
    end
  end

  context 'errored submission' do
    let(:error) { StandardError.new('Connection timeout') }

    before do
      allow_any_instance_of(subject).to receive(:get_file_body).and_raise(error)
    end

    it 'logs the error message and re-raises' do
      expect(service).to receive(:log_job_progress).with(
        claim.id,
        'V2 BD upload job started'
      )
      expect(service).to receive(:log_job_progress).with(
        claim.id,
        'BD failure StandardError: Connection timeout'
      )

      expect { service.perform(claim.id) }.to raise_error(StandardError)
    end

    it 'sets the claim status to errored' do
      expect { service.perform(claim.id) }.to raise_error(StandardError)

      claim.reload
      expect(claim.status).to eq('errored')
    end

    it 'stores the error in evss_response' do
      expect { service.perform(claim.id) }.to raise_error(StandardError)

      claim.reload
      expect(claim.evss_response).to eq([{ 'detail' => 'Connection timeout' }])
    end

    context 'when the error has original_body array payload' do
      let(:error) do
        Common::Exceptions::BackendServiceException.new(
          'pdf.error',
          {},
          500,
          [{ 'detail' => 'service failure' }]
        )
      end

      it 'stores original_body array errors as-is in evss_response' do
        expect { service.perform(claim.id) }.to raise_error(Common::Exceptions::BackendServiceException)

        claim.reload
        expect(claim.evss_response).to eq([{ 'detail' => 'service failure' }])
      end
    end
  end

  context 'when the pdf is mocked' do
    it 'uploads to BD' do
      with_settings(Settings.claims_api.benefits_documents, use_mocks: true) do
        subject.perform_async(claim.id)

        claim.reload
        expect(claim.uploader).to be_a(ClaimsApi::SupportingDocumentUploader)
      end
    end
  end

  describe '#get_file_body' do
    it 'returns the file body correctly' do
      subject.perform_async(claim.id)

      expect(service.send(:get_file_body, claim).blank?).to be(false)
      claim.reload
      expect(claim.uploader).to be_a(ClaimsApi::SupportingDocumentUploader)
    end
  end

  describe 'when an errored job has exhausted its retries' do
    it 'logs to the ClaimsApi Logger' do
      error_msg = 'An error occurred from the BD Uploader Job'
      msg = { 'args' => [claim.id],
              'class' => subject,
              'error_message' => error_msg }

      described_class.within_sidekiq_retries_exhausted_block(msg) do
        expect(ClaimsApi::Logger).to receive(:log).with(
          'claims_api_retries_exhausted',
          record_id: claim.id,
          message: "Job retries exhausted for #{subject}",
          error: error_msg
        )
      end
    end

    it 'sets claim status to errored when retries are exhausted' do
      error_msg = 'An error occurred'
      msg = { 'args' => [claim.id],
              'class' => described_class.to_s,
              'error_message' => error_msg }
      expect(claim.status).to eq('pending')

      # Get the sidekiq_retries_exhausted handler proc and call it directly
      handler = described_class.sidekiq_retries_exhausted_block
      handler.call(msg)

      # Verify the claim was updated
      claim.reload
      expect(claim.status).to eq('errored')
    end

    context 'when the error message is present' do
      it 'sets evss_response to the error when retries are exhausted' do
        error_msg = 'An error occurred'
        msg = { 'args' => [claim.id],
                'class' => described_class.to_s,
                'error_message' => error_msg }
        expect(claim.evss_response).to be_nil

        handler = described_class.sidekiq_retries_exhausted_block
        handler.call(msg)

        claim.reload
        expect(claim.evss_response).to eq(error_msg)
      end
    end

    context 'when the error message is not present' do
      it 'sets claim status to errored and evss_response when retries are exhausted' do
        error_msg = nil
        msg = { 'args' => [claim.id],
                'class' => described_class.to_s,
                'error_message' => error_msg }
        expect(claim.evss_response).to be_nil

        handler = described_class.sidekiq_retries_exhausted_block
        handler.call(msg)

        claim.reload
        expect(claim.evss_response).to eq('Job retries exhausted')
      end
    end
  end

  describe 'when an errored job has a time limitation' do
    it 'retries for 48 hours' do
      expect(described_class.get_sidekiq_options['retry_for']).to eq(48.hours)
    end
  end
end
