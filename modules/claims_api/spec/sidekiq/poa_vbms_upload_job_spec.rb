# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ClaimsApi::PoaVBMSUploadJob, type: :job do
  subject { described_class }

  before do
    Sidekiq::Job.clear_all
    allow(Flipper).to receive(:enabled?).with(:claims_load_testing).and_return false
    allow_any_instance_of(ClaimsApi::V2::BenefitsDocuments::Service)
      .to receive(:get_auth_token).and_return('some-value-here')
  end

  let(:user) { create(:user, :loa3) }
  let(:auth_headers) do
    headers = EVSS::DisabilityCompensationAuthHeaders.new(user).add_headers(EVSS::AuthHeaders.new(user).to_h)
    headers['va_eauth_pnid'] = '796104437'
    headers
  end

  describe '#stream_to_temp_file' do
    it 'converts a stream to a temp file' do
      expect(described_class.new.stream_to_temp_file(StringIO.new)).to be_a Tempfile
    end
  end

  describe '#fetch_file_path' do
    subject { described_class.new.fetch_file_path(fake_uploader) }

    let(:fake_uploader) do
      OpenStruct.new file: OpenStruct.new(url: nil, file: fake_uploader_path)
    end
    let(:fake_uploader_path) { Object.new }

    context 'uploads disabled' do
      with_settings(Settings.evss.s3, uploads_enabled: false) do
        it 'returns uploaders file path' do
          expect(subject).to be fake_uploader_path
        end
      end
    end

    context 'uploads enabled' do
      context 'OpenURI returns a StringIO' do
        it 'returns a path' do
          with_settings(Settings.evss.s3, uploads_enabled: true) do
            allow(URI).to receive(:parse).and_return(OpenStruct.new(open: StringIO.new))
            expect(subject).to be_a String
            expect(subject).not_to be_empty
          end
        end
      end

      context 'OpenURI returns a Tempfile' do
        it 'returns a path' do
          with_settings(Settings.evss.s3, 'uploads_enabled' => true) do
            allow(URI).to receive(:parse).and_return(OpenStruct.new(open: Tempfile.new))
            expect(subject).to be_a String
            expect(subject).not_to be_empty
          end
        end
      end
    end
  end

  describe 'when an errored job has exhausted its retries' do
    it 'logs to the ClaimsApi Logger' do
      poa = create_poa
      error_msg = 'An error occurred for the POA VBMS Upload Job'
      msg = { 'args' => [poa.id],
              'class' => subject,
              'error_message' => error_msg }

      described_class.within_sidekiq_retries_exhausted_block(msg) do
        expect(ClaimsApi::Logger).to receive(:log).with(
          'claims_api_retries_exhausted',
          record_id: poa.id,
          message: "Job retries exhausted for #{subject}",
          error: error_msg
        )
      end
    end
  end

  describe 'uploading to benefits documents' do
    let(:power_of_attorney) { create_poa }

    context "the 'post' action" do
      it 'calls the PoaDocumentService with doc_type L075' do
        allow_any_instance_of(BGS::VetRecordWebService).to receive(:update_birls_record)
          .and_return({ return_code: 'BMOD0001' })
        expect_any_instance_of(ClaimsApi::PoaDocumentService).to receive(:create_upload).with(
          poa: power_of_attorney,
          pdf_path: anything,
          doc_type: power_of_attorney.file_data['doc_type'],
          action: 'post'
        )
        subject.new.perform(power_of_attorney.id)
      end

      it 'rescues errors and sets the status to errored' do
        error_message = 'BackendServiceException: {:status=>400, :detail=>nil, :code=>"VA900", :source=>nil}'

        expect do
          VCR.use_cassette('claims_api/bd/upload_error') do
            subject.new.perform(power_of_attorney.id)
          end
        end.to raise_error(Common::Exceptions::BackendServiceException, error_message)

        power_of_attorney.reload
        expect(power_of_attorney.status).to eq(ClaimsApi::PowerOfAttorney::ERRORED)
        expect(power_of_attorney.vbms_error_message).to eq(error_message)
      end
    end

    context "when the 'put' action is sent" do
      it 'calls the PoaDocumentService with the correct action' do
        expect_any_instance_of(ClaimsApi::PoaDocumentService).to receive(:create_upload).with(
          poa: power_of_attorney,
          pdf_path: anything,
          doc_type: power_of_attorney.file_data['doc_type'],
          action: 'put'
        )
        subject.new.perform(power_of_attorney.id, 'put')
      end
    end

    context 'with errors' do
      it 'retries the job if there is a failure' do
        VCR.use_cassette('claims_api/poa_vbms_upload_job/bd/document_upload_500') do
          expect(ClaimsApi::PoaUpdater).not_to receive(:perform_async)

          expect { subject.new.perform(power_of_attorney.id) }
            .to raise_error(Common::Exceptions::BackendServiceException)
          power_of_attorney.reload

          expect(power_of_attorney.status).to eq('errored')
          expect(power_of_attorney.vbms_error_message).to eq(
            'BackendServiceException: {:status=>500, :detail=>nil, :code=>"VA900", :source=>nil}'
          )
        end
      end

      it 'rescues file not found from S3, updates POA record, and re-raises to allow Sidekiq retries' do
        allow_any_instance_of(described_class).to receive(:benefits_doc_upload).and_raise(Errno::ENOENT)

        expect { subject.new.perform(power_of_attorney.id) }.to raise_error(Errno::ENOENT)
        power_of_attorney.reload

        expect(power_of_attorney.status).to eq('errored')
        expect(power_of_attorney.vbms_error_message).to eq(
          'File could not be retrieved from AWS'
        )
      end
    end
  end

  describe 'when uploading a PDF for a dependent' do
    let(:power_of_attorney) { create_poa }
    let(:action) { 'put' }

    before do
      power_of_attorney.update(
        auth_headers: power_of_attorney.auth_headers.merge(
          'dependent' => { 'participant_id' => '000000000000', ssn: '111111111' }
        )
      )
    end

    it 'calls the PoaAssignDependentClaimantJob instead of the PoaUpdater for put requests' do
      expect_any_instance_of(ClaimsApi::PoaDocumentService).to receive(:create_upload).with(
        poa: power_of_attorney,
        pdf_path: anything,
        doc_type: power_of_attorney.file_data['doc_type'],
        action:
      )
      expect(ClaimsApi::PoaAssignDependentClaimantJob).to receive(:perform_async).with(power_of_attorney.id)
      expect(ClaimsApi::PoaUpdater).not_to receive(:perform_async)

      subject.new.perform(power_of_attorney.id, action)
    end
  end

  private

  def create_poa
    poa = create(:power_of_attorney_with_doc, doc_type: 'L075')
    poa.auth_headers = auth_headers
    poa.save
    poa
  end
end
