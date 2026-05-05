# frozen_string_literal: true

require 'rails_helper'

describe TravelPay::DocumentsService do
  let(:user) { build(:user) }
  let(:client) { instance_double(TravelPay::DocumentsClient) }
  let(:auth_manager) { instance_double(TravelPay::AuthManager) }
  let(:auth_session) { TravelPay::AuthSession.new(veis_token: 'veis_token', btsss_token: 'btsss_token') }
  let(:service) { described_class.new(auth_manager) }
  let(:doc_summary_data) do
    double(body: { 'data' => [{
             'documentId' => 'doc_id',
             'filename' => 'doc.pdf',
             'mimetype' => 'application/pdf',
             'createdon' => '2023-10-01T00:00:00Z'
           }] }, headers: {})
  end
  let(:doc_binary_data) do
    double(body: '{ "data": "binary_data"}',
           headers: {
             'Content-Disposition' => 'attachment; filename="doc.pdf"',
             'Content-Type' => 'application/pdf',
             'Content-Length' => 12_345
           })
  end
  let(:upload_response) { double(body: { 'data' => { 'documentId' => '123e4567-e89b-12d3-a456-426614174000' } }) }
  let(:claim_id) { '73611905-71bf-46ed-b1ec-e790593b8565' }
  let(:doc_id) { '123e4567-e89b-12d3-a456-426614174000' }

  before do
    allow_any_instance_of(TravelPay::DocumentsClient).to receive(:get_document_binary).and_return(doc_binary_data)
    allow(auth_manager).to receive_messages(authorize: auth_session, user:)
  end

  describe '#get_document_summaries' do
    before do
      allow_any_instance_of(TravelPay::DocumentsClient).to receive(:get_document_ids).and_return(doc_summary_data)
    end

    it 'calls the client to get document IDs' do
      expect_any_instance_of(TravelPay::DocumentsClient).to receive(:get_document_ids).with(auth_session, 'claim_id')
      service.get_document_summaries('claim_id')
    end
  end

  describe '#download_document' do
    before do
      allow_any_instance_of(TravelPay::DocumentsClient).to receive(:get_document_binary).and_return(doc_binary_data)
    end

    it 'calls the client to get document binary' do
      params = { claim_id: 'claim_id', doc_id: 'doc_id' }
      expect_any_instance_of(TravelPay::DocumentsClient).to receive(:get_document_binary).with(auth_session, params)
      service.download_document(*params.values)
    end

    it 'sends the type and disposition headers of the original response' do
      params = { claim_id: 'claim_id', doc_id: 'doc_id' }
      allow(client).to receive(:get_document_binary).and_return(doc_binary_data)
      result = service.download_document(*params.values)
      expect(result[:disposition]).to include('filename="doc.pdf"')
      expect(result[:type]).to eq('application/pdf')
      expect(result[:content_length]).to eq(12_345)
    end

    it 'includes the filename in the returned hash' do
      params = { claim_id: 'claim_id', doc_id: 'doc_id' }
      allow(client).to receive(:get_document_binary).and_return(doc_binary_data)
      result = service.download_document(*params.values)
      expect(result[:filename]).to eq('doc.pdf')
    end
  end

  describe '#upload_document' do
    let(:file_path) { 'modules/travel_pay/spec/fixtures/documents/test.pdf' }
    # Have to set the filename here since Rack::Test::UploadedFile creates a tempfile under /tmp with a unique name
    let(:file) { Rack::Test::UploadedFile.new(file_path, 'application/pdf', 'test.pdf') }

    before do
      allow_any_instance_of(TravelPay::DocumentsClient).to receive(:add_document).and_return(upload_response)
    end

    it 'calls the client to upload the document' do
      expect_any_instance_of(TravelPay::DocumentsClient).to receive(:add_document).with(
        auth_session,
        hash_including(claim_id:, document: file)
      )
      service.upload_document(claim_id, file)
    end

    it 'returns the data from the response body' do
      result = service.upload_document(claim_id, file)
      expect(result).to eq({ 'documentId' => '123e4567-e89b-12d3-a456-426614174000' })
    end

    it 'raises ArgumentError when claim_id is missing' do
      expect { service.upload_document(nil, file) }.to raise_error(
        ArgumentError,
        /Missing Claim ID/
      )
    end

    it 'raises ArgumentError when document is missing' do
      expect { service.upload_document(claim_id, nil) }.to raise_error(
        ArgumentError,
        /Missing Claim ID or Uploaded Document/
      )
    end

    context 'when document type is invalid' do
      let(:invalid_file) do
        tf = Tempfile.new(['invalid', '.txt'])
        Rack::Test::UploadedFile.new(tf.path, 'text/plain')
      end

      it 'raises a Common::Exceptions::BadRequest' do
        expect { service.upload_document(claim_id, invalid_file) }.to raise_error(
          Common::Exceptions::BadRequest
        )
      end
    end

    context 'when document is HEIC' do
      let(:heic_file) do
        heic_path = Rails.root.join('modules', 'travel_pay', 'spec', 'fixtures', 'pixel-working.heic')
        Rack::Test::UploadedFile.new(heic_path, 'image/heic')
      end

      context 'when HEIC conversion feature flag is enabled' do
        before do
          allow(auth_manager).to receive(:user).and_return(user)
          allow(Flipper).to receive(:enabled?).with(:travel_pay_enable_heic_conversion, user).and_return(true)
        end

        it 'converts the HEIC document to JPG before uploading' do
          converted_doc = nil
          expect_any_instance_of(TravelPay::DocumentsClient).to receive(:add_document) do |_instance, session, params|
            expect(session).to eq(auth_session)
            expect(params[:claim_id]).to eq(claim_id)
            converted_doc = params[:document]
            expect(converted_doc).to be_an_instance_of(ActionDispatch::Http::UploadedFile)
            upload_response
          end

          result = service.upload_document(claim_id, heic_file)
          expect(result).to eq({ 'documentId' => '123e4567-e89b-12d3-a456-426614174000' })
          expect(File.extname(converted_doc.original_filename)).to eq('.jpg')
          expect(converted_doc.content_type).to eq('image/jpeg')
        end
      end

      context 'when HEIC conversion feature flag is disabled' do
        before do
          allow(auth_manager).to receive(:user).and_return(user)
          allow(Flipper).to receive(:enabled?).with(:travel_pay_enable_heic_conversion, user).and_return(false)
        end

        it 'raises a Common::Exceptions::BadRequest for HEIC files' do
          expect { service.upload_document(claim_id, heic_file) }.to raise_error(
            Common::Exceptions::BadRequest
          )
        end
      end
    end

    context 'when document is HEIF' do
      let(:heif_file) do
        heic_path = Rails.root.join('modules', 'travel_pay', 'spec', 'fixtures', 'pixel-working.heic')
        tf = Tempfile.new(['test', '.heif'])
        tf.binmode
        tf.write(File.binread(heic_path))
        tf.rewind
        Rack::Test::UploadedFile.new(tf.path, 'image/heif')
      end

      before do
        allow(auth_manager).to receive(:user).and_return(user)
        allow(Flipper).to receive(:enabled?).with(:travel_pay_enable_heic_conversion, user).and_return(true)
      end

      it 'allows and converts HEIF files when feature flag is enabled' do
        converted_doc = nil
        allow_any_instance_of(TravelPay::DocumentsClient).to receive(:add_document) do |_instance, _session, params|
          converted_doc = params[:document]
          upload_response
        end

        expect { service.upload_document(claim_id, heif_file) }.not_to raise_error
        expect(File.extname(converted_doc.original_filename)).to eq('.jpg')
        expect(converted_doc.content_type).to eq('image/jpeg')
      end
    end

    context 'when document size is invalid' do
      let(:oversized_pdf_file) do
        tf = Tempfile.new(['oversized', '.pdf'])
        tf.binmode # switches the Tempfile into binary mode
        # increase the file size to exceed 5 MB
        tf.write('0' * ((5 * 1024 * 1024) + 1))
        tf.rewind # makes sure the uploaded file is actually readable as expected after writing to it.
        Rack::Test::UploadedFile.new(tf.path, 'application/pdf')
      end

      it 'raises a Common::Exceptions::BadRequest' do
        expect { service.upload_document(claim_id, oversized_pdf_file) }.to raise_error(
          Common::Exceptions::BadRequest
        )
      end
    end
  end

  describe '#delete_document' do
    let(:delete_response) do
      double(body: { 'data' => { 'documentId' => doc_id } })
    end

    before do
      allow_any_instance_of(TravelPay::DocumentsClient).to receive(:delete_document).and_return(delete_response)
    end

    it 'calls the client to delete the document' do
      expect_any_instance_of(TravelPay::DocumentsClient).to receive(:delete_document).with(
        auth_session,
        hash_including(claim_id:, document_id: doc_id)
      )
      service.delete_document(claim_id, doc_id)
    end

    it 'returns the data from the response body' do
      result = service.delete_document(claim_id, doc_id)
      expect(result).to eq({ 'documentId' => doc_id })
    end

    it 'raises ArgumentError when claim_id is missing' do
      expect { service.delete_document(nil, doc_id) }.to raise_error(
        ArgumentError,
        /Missing Claim ID/
      )
    end

    it 'raises ArgumentError when document_id is missing' do
      expect { service.delete_document(claim_id, nil) }.to raise_error(
        ArgumentError,
        /Missing Claim ID or Document ID/
      )
    end
  end
end
