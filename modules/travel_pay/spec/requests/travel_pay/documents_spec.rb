# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TravelPay::V0::DocumentsController, type: :request do
  include TravelPay::Engine.routes.url_helpers

  let(:claim_id) { '73611905-71bf-46ed-b1ec-e790593b8565' }
  let(:doc_id) { '123e4567-e89b-12d3-a456-426614174000' }
  let(:user) { build(:user) }
  let(:service) { instance_double(TravelPay::DocumentsService) }
  let(:valid_document) do
    Rack::Test::UploadedFile.new('modules/travel_pay/spec/fixtures/documents/test.pdf')
  end
  let(:poa_document) do
    Rack::Test::UploadedFile.new(
      'modules/travel_pay/spec/fixtures/documents/test.pdf',
      'application/pdf',
      original_filename: 'proof-of-attendance.pdf'
    )
  end

  before do
    allow_any_instance_of(TravelPay::AuthManager).to receive(:authorize)
      .and_return(TravelPay::AuthSession.new(veis_token: 'veis_token',
                                             btsss_token: 'btsss_token'))
    sign_in(user)
    allow(Flipper).to receive(:enabled?).with(:travel_pay_power_switch, instance_of(User)).and_return(true)
  end

  # GET /travel_pay/v0/claims/:claim_id/documents/:id
  describe 'show' do
    headers = { 'Authorization' => 'Bearer vagov_token' }
    filename = 'AppealForm.pdf'

    context 'when the document is successfully retrieved' do
      it 'returns the document data with correct headers' do
        VCR.use_cassette('travel_pay/documents/get/success_pdf', match_requests_on: %i[method path]) do
          get(doc_path, headers:)

          expect(response).to have_http_status(:ok)
          expect(response.body).not_to be_empty
          expect(response.headers['Content-Type']).to eq('application/pdf')
          expect(response.headers['Content-Disposition']).to include(filename)
          expect(response.headers['Content-Length']).to be_present
        end
      end
    end

    context 'when the document is not found' do
      it 'returns a 404 error' do
        VCR.use_cassette('travel_pay/documents/get/not_found', match_requests_on: %i[method path]) do
          get(doc_path('bad-id'), headers:)

          expect(response).to have_http_status(:not_found)
          body = JSON.parse(response.body)
          expect(body['errors']).to be_present
        end
      end
    end

    context 'when an unhandled error occurs' do
      it 'logs the error and returns error response' do
        VCR.use_cassette('travel_pay/documents/get/internal_error', match_requests_on: %i[method path]) do
          get(doc_path('big-bad-error'), headers:)

          expect(response).to have_http_status(:bad_gateway)
          body = JSON.parse(response.body)
          expect(body['errors']).to be_present
        end
      end
    end
  end

  # DELETE /travel_pay/v0/claims/:claim_id/documents/:id
  describe 'destroy' do
    before do
      allow_any_instance_of(TravelPay::V0::DocumentsController).to receive(:current_user).and_return(user)
    end

    context 'when feature flag is enabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:travel_pay_enable_complex_claims, instance_of(User)).and_return(true)
      end

      context 'vcr tests' do
        context 'when the document is successfully deleted' do
          it 'returns the document data with correct headers' do
            VCR.use_cassette('travel_pay/documents/delete/success', match_requests_on: %i[method path]) do
              delete(doc_path)

              expect(response).to have_http_status(:ok)
              body = JSON.parse(response.body)

              expect(body['documentId']).to eq('123e4567-e89b-12d3-a456-426614174000')
            end
          end
        end
      end

      context 'stubbed service behavior' do
        before do
          allow_any_instance_of(TravelPay::V0::DocumentsController)
            .to receive(:service).and_return(service)
        end

        it 'deletes document and returns documentId' do
          allow(service).to receive(:delete_document)
            .with(claim_id, doc_id)
            .and_return({ 'documentId' => '123e4567-e89b-12d3-a456-426614174000' })

          delete(doc_path)

          expect(response).to have_http_status(:ok)
          expect(JSON.parse(response.body)).to eq('documentId' => '123e4567-e89b-12d3-a456-426614174000')
        end

        it 'returns bad request when claim_id is invalid' do
          invalid_claim_id = 'invalid$'

          delete("/travel_pay/v0/claims/#{invalid_claim_id}/documents/123e4567-e89b-12d3-a456-426614174000")

          expect(response).to have_http_status(:bad_request)
          body = JSON.parse(response.body)
          expect(body['errors'].first['detail']).to eq('Claim ID is invalid')
        end

        it 'returns bad request when document_id is invalid' do
          invalid_doc_id = 'bad!!'

          delete("/travel_pay/v0/claims/#{claim_id}/documents/#{invalid_doc_id}")

          expect(response).to have_http_status(:bad_request)
          body = JSON.parse(response.body)
          expect(body['errors'].first['detail']).to eq('Document ID is invalid')
        end

        it 'returns not found when Faraday::ResourceNotFound' do
          exception = Faraday::ResourceNotFound.new('Not found')
          allow(service).to receive(:delete_document).and_raise(exception)

          delete(doc_path)

          expect(response).to have_http_status(:not_found)
          body = JSON.parse(response.body)
          expect(body['errors']).to be_present
        end

        it 'returns error JSON when Faraday::ClientError' do
          error = Faraday::ClientError.new('Bad request')
          allow(service).to receive(:delete_document).and_raise(error)

          delete(doc_path)

          expect(response).to have_http_status(:service_unavailable)
          body = JSON.parse(response.body)
          expect(body['errors']).to be_present
          expect(body['errors'].first['code']).to eq('BTSSS-API_CONNECTION_FAILED')
        end

        it 'returns error JSON when Faraday::ServerError' do
          error = Faraday::ServerError.new('Internal server error')
          allow(service).to receive(:delete_document).and_raise(error)

          delete(doc_path)

          expect(response).to have_http_status(:service_unavailable)
          body = JSON.parse(response.body)
          expect(body['errors']).to be_present
          expect(body['errors'].first['code']).to eq('BTSSS-API_CONNECTION_FAILED')
        end
      end
    end
  end

  # POST /travel_pay/v0/claims/:claim_id/documents
  describe '#create' do
    before do
      allow_any_instance_of(TravelPay::V0::DocumentsController).to receive(:current_user).and_return(user)
    end

    context 'when feature flag is enabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:travel_pay_enable_complex_claims, instance_of(User)).and_return(true)
      end

      context 'stubbed service behavior' do
        before do
          allow(service).to receive(:upload_document)
            .with(claim_id, kind_of(ActionDispatch::Http::UploadedFile))
            .and_return({ 'documentId' => 'abc-123' })
          allow_any_instance_of(TravelPay::V0::DocumentsController)
            .to receive(:service).and_return(service)
        end

        it 'uploads document and returns documentId' do
          post("/travel_pay/v0/claims/#{claim_id}/documents", params: { Document: valid_document })

          expect(response).to have_http_status(:created)
          expect(JSON.parse(response.body)).to eq('documentId' => 'abc-123')
        end

        it 'returns bad request when document param is missing' do
          post("/travel_pay/v0/claims/#{claim_id}/documents", params: {})

          expect(response).to have_http_status(:bad_request)
          body = JSON.parse(response.body)
          expect(body['errors'].first['detail']).to eq('Document is required')
        end

        # NOTE: In request specs, you can’t make params[:claim_id] truly missing because
        # it’s part of the URL path and Rails routing prevents that.
        it 'returns bad request when claim_id is invalid' do
          invalid_claim_id = 'invalid$' # safe in URL, fails regex \A[\w-]+\z

          post("/travel_pay/v0/claims/#{invalid_claim_id}/documents", params: { Document: valid_document })

          expect(response).to have_http_status(:bad_request)
          body = JSON.parse(response.body)
          expect(body['errors'].first['detail']).to eq('Claim ID is invalid')
        end

        it 'returns not found when Faraday::ResourceNotFound' do
          exception = Faraday::ResourceNotFound.new('Not found')
          allow(service).to receive(:upload_document).and_raise(exception)

          post("/travel_pay/v0/claims/#{claim_id}/documents", params: { Document: valid_document })

          expect(response).to have_http_status(:not_found)
          body = JSON.parse(response.body)
          expect(body['errors']).to be_present
        end

        it 'returns error json when Faraday::Error' do
          error = Faraday::Error.new('ERROR')
          allow(service).to receive(:upload_document).and_raise(error)

          post("/travel_pay/v0/claims/#{claim_id}/documents", params: { Document: valid_document })

          expect(response).to have_http_status(:service_unavailable)
          body = JSON.parse(response.body)
          expect(body['errors']).to be_present
          expect(body['errors'].first['code']).to eq('BTSSS-API_CONNECTION_FAILED')
        end
      end

      context 'statsd metrics' do
        before do
          allow(StatsD).to receive(:increment)
          allow_any_instance_of(TravelPay::V0::DocumentsController)
            .to receive(:service).and_return(service)
        end

        it 'tracks success for non-poa uploads' do
          allow(service).to receive(:upload_document)
            .with(claim_id, kind_of(ActionDispatch::Http::UploadedFile))
            .and_return({ 'documentId' => 'abc-123' })

          post("/travel_pay/v0/claims/#{claim_id}/documents", params: { Document: valid_document })

          expect(response).to have_http_status(:created)
          expect(StatsD).to have_received(:increment).with('travel_pay.documents.create',
                                                           tags: ['document_type:other', 'result:success'])
        end

        it 'tracks success for proof-of-attendance uploads as poa' do
          allow(service).to receive(:upload_document)
            .with(claim_id, kind_of(ActionDispatch::Http::UploadedFile))
            .and_return({ 'documentId' => 'abc-123' })

          post("/travel_pay/v0/claims/#{claim_id}/documents", params: { Document: poa_document })

          expect(response).to have_http_status(:created)
          expect(StatsD).to have_received(:increment).with('travel_pay.documents.create',
                                                           tags: ['document_type:poa', 'result:success'])
        end

        it 'tracks failure when document param is missing' do
          post("/travel_pay/v0/claims/#{claim_id}/documents", params: {})

          expect(response).to have_http_status(:bad_request)
          expect(StatsD).to have_received(:increment).with('travel_pay.documents.create',
                                                           tags: ['document_type:other', 'result:failure'])
        end

        it 'tracks failure when upload raises resource not found' do
          exception = Faraday::ResourceNotFound.new('Not found')
          allow(exception).to receive(:response).and_return(
            request: { headers: { 'X-Correlation-ID' => 'abc' } }
          )
          allow(service).to receive(:upload_document).and_raise(exception)

          post("/travel_pay/v0/claims/#{claim_id}/documents", params: { Document: valid_document })

          expect(response).to have_http_status(:not_found)
          expect(StatsD).to have_received(:increment).with('travel_pay.documents.create',
                                                           tags: ['document_type:other', 'result:failure'])
        end

        it 'tracks failure when upload raises Faraday::Error' do
          error = Faraday::Error.new('ERROR')
          allow(service).to receive(:upload_document).and_raise(error)

          post("/travel_pay/v0/claims/#{claim_id}/documents", params: { Document: valid_document })

          expect(response).to have_http_status(:service_unavailable)
          expect(StatsD).to have_received(:increment).with('travel_pay.documents.create',
                                                           tags: ['document_type:other', 'result:failure'])
        end
      end
    end

    context 'when feature flag disabled' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(:travel_pay_enable_complex_claims, instance_of(User))
          .and_return(false)
      end

      it 'returns 503 Service Unavailable' do
        post("/travel_pay/v0/claims/#{claim_id}/documents", params: { Document: valid_document })

        expect(response).to have_http_status(:service_unavailable)
        body = JSON.parse(response.body)
        expect(body['errors'].first['detail']).to include('Travel Pay document endpoint unavailable per feature toggle')
      end
    end
  end

  def doc_path(doc_id = nil)
    "/travel_pay/v0/claims/#{claim_id}/documents/#{doc_id || '123e4567-e89b-12d3-a456-426614174000'}"
  end
end
