# frozen_string_literal: true

require 'rails_helper'
require 'unified_health_data/ccd_service'
require 'support/shared_contexts/uhd_security_endpoint'

RSpec.describe 'MyHealth::V2::CcdController', type: :request do
  include_context 'uhd legacy security endpoint'

  let(:user_id) { '11898795' }
  let(:current_user) { build(:user, :mhv, icn: '1000123456V123456') }

  before do
    sign_in_as(current_user, stub_mhv_account: true)
  end

  describe 'GET /my_health/v2/medical_records/ccd/generate' do
    let(:generate_path) { '/my_health/v2/medical_records/ccd/generate' }
    let(:generate_cassette) { 'unified_health_data/get_ccd_generate_202' }

    before do
      Timecop.freeze(Time.zone.parse('2026-03-10'))
    end

    after do
      Timecop.return
    end

    context 'when CCD generation is successfully initiated' do
      it 'returns 202 accepted with JSONAPI serialized job metadata' do
        VCR.use_cassette(generate_cassette, match_requests_on: %i[method path]) do
          get generate_path

          expect(response).to have_http_status(:accepted)
          json_response = JSON.parse(response.body)
          expect(json_response['data']['type']).to eq('ccd_status')
          expect(json_response['data']['id']).to be_present

          attributes = json_response['data']['attributes']
          expect(attributes['status']).to eq('NOT_READY')
          expect(attributes['job_id']).to be_present
          expect(attributes['source']).to eq('oracle-health')
          expect(attributes['message']).to include('awaiting task correlation')
          expect(attributes['retry_after_seconds']).to eq(10)
        end
      end
    end

    context 'when a job id is returned' do
      let(:job_id) { 'b0733653-30b4-411f-a997-7453039e510c' }

      it 'records the job owner against the current user' do
        cache = ActiveSupport::Cache::MemoryStore.new
        allow(Rails).to receive(:cache).and_return(cache)

        VCR.use_cassette(generate_cassette, match_requests_on: %i[method path]) do
          get generate_path
        end

        expect(cache.read("uhd:ccd_job_owner:#{job_id}")).to be_present
      end
    end

    context 'when SCDF API error occurs' do
      let(:service_double) { instance_double(UnifiedHealthData::CcdService) }
      let(:client_error) do
        Common::Client::Errors::ClientError.new('SCDF service unavailable', 503)
      end

      before do
        allow(UnifiedHealthData::CcdService).to receive(:new).and_return(service_double)
        allow(service_double).to receive(:initiate_ccd).and_raise(client_error)
      end

      it 'returns 502 bad gateway for upstream 5xx errors' do
        get generate_path

        expect(response).to have_http_status(:bad_gateway)
        json_response = JSON.parse(response.body)
        expect(json_response['errors'].first['title']).to eq('SCDF API Error')
      end
    end

    context 'when backend service exception occurs' do
      let(:service_double) { instance_double(UnifiedHealthData::CcdService) }

      before do
        allow(UnifiedHealthData::CcdService).to receive(:new).and_return(service_double)
        allow(service_double).to receive(:initiate_ccd)
          .and_raise(Common::Exceptions::BackendServiceException.new(nil, {}, 502, 'Backend failure'))
      end

      it 'returns 502 bad gateway' do
        get generate_path

        expect(response).to have_http_status(:bad_gateway)
        json_response = JSON.parse(response.body)
        expect(json_response['errors']).to be_present
      end
    end

    context 'when unexpected error occurs' do
      let(:service_double) { instance_double(UnifiedHealthData::CcdService) }

      before do
        allow(UnifiedHealthData::CcdService).to receive(:new).and_return(service_double)
        allow(service_double).to receive(:initiate_ccd).and_raise(StandardError, 'Unexpected client error')
      end

      it 'returns 500 internal server error' do
        get generate_path

        expect(response).to have_http_status(:internal_server_error)
        json_response = JSON.parse(response.body)
        expect(json_response['errors'].first['title']).to eq('Internal Server Error')
        expect(json_response['errors'].first['detail']).to include('unexpected error')
      end
    end
  end

  describe 'GET /my_health/v2/medical_records/ccd/status/:job_id' do
    let(:job_id) { '12043' }
    let(:status_path) { "/my_health/v2/medical_records/ccd/status/#{job_id}" }
    let(:status_cassette) { 'unified_health_data/get_ccd_status_202' }
    let(:owned_ccd_jobs) { [UnifiedHealthData::Ccd.new(job_id:, task_id: job_id)] }

    before do
      allow_any_instance_of(UnifiedHealthData::CcdService)
        .to receive(:get_ccd_jobs).and_return(owned_ccd_jobs)
    end

    context 'when CCD is still processing' do
      it 'returns 202 with JSONAPI serialized status metadata' do
        VCR.use_cassette(status_cassette, match_requests_on: %i[method path]) do
          get status_path

          expect(response).to have_http_status(:accepted)
          json_response = JSON.parse(response.body)
          expect(json_response['data']['type']).to eq('ccd_status')
          expect(json_response['data']['id']).to eq(job_id)

          attributes = json_response['data']['attributes']
          expect(attributes['status']).to eq('NOT_READY')
          expect(attributes['job_id']).to eq(job_id)
          expect(attributes['task_id']).to eq(job_id)
          expect(attributes['source']).to eq('oracle-health')
          expect(attributes['message']).to include('processing')
          expect(attributes['retry_after_seconds']).to eq(10)
        end
      end
    end

    context 'when a status response includes a correlated task id' do
      it 'records the task owner in the cache' do
        cache = ActiveSupport::Cache::MemoryStore.new
        allow(Rails).to receive(:cache).and_return(cache)

        VCR.use_cassette(status_cassette, match_requests_on: %i[method path]) do
          get status_path
        end

        expect(cache.read("uhd:ccd_job_owner:#{job_id}")).to be_present
      end
    end

    context 'when CCD generation is complete' do
      let(:success_cassette) { 'unified_health_data/get_ccd_success_200' }

      it 'returns 200 with JSONAPI serialized CCD metadata and format statuses' do
        VCR.use_cassette(success_cassette, match_requests_on: %i[method path]) do
          get status_path

          expect(response).to have_http_status(:ok)
          json_response = JSON.parse(response.body)
          expect(json_response['data']['type']).to eq('ccd_status')
          expect(json_response['data']['id']).to eq(job_id)

          attributes = json_response['data']['attributes']
          expect(attributes['job_id']).to eq(job_id)
          expect(attributes['task_id']).to eq(job_id)
          expect(attributes['source']).to eq('oracle-health')
          expect(attributes['message']).to eq('Success')
          expect(attributes['authored_on']).to eq('2026-03-03T10:18:36.400-05:00')
          expect(attributes['xml']).to eq('READY')
          expect(attributes['html']).to eq('READY')
          expect(attributes['pdf']).to eq('READY')
        end
      end
    end

    context 'when SCDF API error occurs' do
      let(:service_double) { instance_double(UnifiedHealthData::CcdService) }
      let(:client_error) do
        Common::Client::Errors::ClientError.new('SCDF service unavailable', 503)
      end

      before do
        allow(UnifiedHealthData::CcdService).to receive(:new).and_return(service_double)
        allow(service_double).to receive(:get_ccd_jobs).and_return(owned_ccd_jobs)
        allow(service_double).to receive(:get_ccd_status).and_raise(client_error)
      end

      it 'returns 502 bad gateway for upstream 5xx errors' do
        get status_path

        expect(response).to have_http_status(:bad_gateway)
        json_response = JSON.parse(response.body)
        expect(json_response['errors'].first['title']).to eq('SCDF API Error')
      end
    end

    context 'when backend service exception occurs' do
      let(:service_double) { instance_double(UnifiedHealthData::CcdService) }

      before do
        allow(UnifiedHealthData::CcdService).to receive(:new).and_return(service_double)
        allow(service_double).to receive(:get_ccd_jobs).and_return(owned_ccd_jobs)
        allow(service_double).to receive(:get_ccd_status)
          .and_raise(Common::Exceptions::BackendServiceException.new(nil, {}, 502, 'Backend failure'))
      end

      it 'returns 502 bad gateway' do
        get status_path

        expect(response).to have_http_status(:bad_gateway)
        json_response = JSON.parse(response.body)
        expect(json_response['errors']).to be_present
      end
    end

    context 'when unexpected error occurs' do
      let(:service_double) { instance_double(UnifiedHealthData::CcdService) }

      before do
        allow(UnifiedHealthData::CcdService).to receive(:new).and_return(service_double)
        allow(service_double).to receive(:get_ccd_jobs).and_return(owned_ccd_jobs)
        allow(service_double).to receive(:get_ccd_status).and_raise(StandardError, 'Unexpected client error')
      end

      it 'returns 500 internal server error' do
        get status_path

        expect(response).to have_http_status(:internal_server_error)
        json_response = JSON.parse(response.body)
        expect(json_response['errors'].first['title']).to eq('Internal Server Error')
        expect(json_response['errors'].first['detail']).to include('unexpected error')
      end
    end

    context 'when the CCD job does not belong to the user' do
      before do
        allow_any_instance_of(UnifiedHealthData::CcdService)
          .to receive(:get_ccd_jobs)
          .and_return([UnifiedHealthData::Ccd.new(job_id: '99999', task_id: '99999')])
      end

      it 'returns 404 not found without calling the status service' do
        expect_any_instance_of(UnifiedHealthData::CcdService).not_to receive(:get_ccd_status)

        get status_path

        expect(response).to have_http_status(:not_found)
        json_response = JSON.parse(response.body)
        expect(json_response['errors'].first['title']).to eq('CCD Not Found')
        expect(json_response['errors'].first['detail']).to eq('The requested CCD is not available')
      end
    end

    context 'when the ownership lookup fails upstream' do
      let(:service_double) { instance_double(UnifiedHealthData::CcdService) }
      let(:client_error) do
        Common::Client::Errors::ClientError.new('SCDF service unavailable', 503)
      end

      before do
        allow(UnifiedHealthData::CcdService).to receive(:new).and_return(service_double)
        allow(service_double).to receive(:get_ccd_jobs).and_raise(client_error)
      end

      it 'surfaces the upstream error instead of a 404 and does not call the status service' do
        expect(service_double).not_to receive(:get_ccd_status)

        get status_path

        expect(response).to have_http_status(:bad_gateway)
        json_response = JSON.parse(response.body)
        expect(json_response['errors'].first['title']).to eq('SCDF API Error')
      end
    end

    context 'when polling with an owned pre-correlation UUID job id' do
      let(:job_id) { 'b0733653-30b4-411f-a997-7453039e510c' }
      let(:generated_ccd) { UnifiedHealthData::Ccd.new(job_id:, source: 'oracle-health', http_status: 202) }
      let(:not_ready_ccd) do
        UnifiedHealthData::Ccd.new(job_id:, task_id: job_id, source: 'oracle-health',
                                   message: 'processing', retry_after_seconds: 10, http_status: 202)
      end

      before do
        allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
        allow_any_instance_of(UnifiedHealthData::CcdService).to receive(:initiate_ccd).and_return(generated_ccd)
        allow_any_instance_of(UnifiedHealthData::CcdService)
          .to receive(:get_ccd_status).with(job_id:).and_return(not_ready_ccd)
      end

      it 'returns the status for a UUID recorded for the current user at generation' do
        get '/my_health/v2/medical_records/ccd/generate'
        get status_path

        expect(response).to have_http_status(:accepted)
      end
    end

    context 'when the UUID job id belongs to another user' do
      let(:job_id) { 'b0733653-30b4-411f-a997-7453039e510c' }

      before do
        allow(Rails.cache).to receive(:read).and_call_original
        allow(Rails.cache).to receive(:read)
          .with("uhd:ccd_job_owner:#{job_id}").and_return('1999999999V999999')
      end

      it 'returns 404 not found without calling the status service' do
        expect_any_instance_of(UnifiedHealthData::CcdService).not_to receive(:get_ccd_status)

        get status_path

        expect(response).to have_http_status(:not_found)
        json_response = JSON.parse(response.body)
        expect(json_response['errors'].first['title']).to eq('CCD Not Found')
        expect(json_response['errors'].first['detail']).to eq('The requested CCD is not available')
      end
    end

    context 'when the job id is an arbitrary non-numeric value' do
      let(:job_id) { 'not-a-valid-id' }

      it 'returns 404 not found without calling the status service' do
        expect_any_instance_of(UnifiedHealthData::CcdService).not_to receive(:get_ccd_status)

        get status_path

        expect(response).to have_http_status(:not_found)
        json_response = JSON.parse(response.body)
        expect(json_response['errors'].first['title']).to eq('CCD Not Found')
      end
    end
  end

  describe 'GET /my_health/v2/medical_records/ccd/download/:job_id' do
    let(:job_id) { '12043' }
    let(:download_path) { "/my_health/v2/medical_records/ccd/download/#{job_id}" }
    let(:success_cassette) { 'unified_health_data/get_ccd_success_200' }
    let(:s3_host_pattern) { /mhv-[\w-]+-uhd-docstore\.s3[.-]us-gov-west-1\.amazonaws\.com/ }
    let(:owned_ccd_jobs) { [UnifiedHealthData::Ccd.new(job_id:, task_id: job_id)] }

    before do
      allow_any_instance_of(UnifiedHealthData::CcdService)
        .to receive(:get_ccd_jobs).and_return(owned_ccd_jobs)
    end

    context 'when the jobs list lags but ownership was cached during generate/poll' do
      let(:job_uuid) { 'b0733653-30b4-411f-a997-7453039e510c' }
      let(:generated_ccd) { UnifiedHealthData::Ccd.new(job_id: job_uuid, source: 'oracle-health', http_status: 202) }
      let(:not_ready_ccd) do
        UnifiedHealthData::Ccd.new(job_id: job_uuid, task_id: job_id, source: 'oracle-health', http_status: 202)
      end
      let(:xml_cassette) { 'unified_health_data/get_ccd_s3_download_xml' }

      before do
        allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
        allow_any_instance_of(UnifiedHealthData::CcdService).to receive(:get_ccd_jobs).and_return([])
        allow_any_instance_of(UnifiedHealthData::CcdService).to receive(:initiate_ccd).and_return(generated_ccd)
        allow_any_instance_of(UnifiedHealthData::CcdService)
          .to receive(:get_ccd_status).with(job_id: job_uuid).and_return(not_ready_ccd)
      end

      it 'allows the numeric download via the cached owner even when the jobs list is empty' do
        # generate caches the UUID owner; the status poll caches the numeric task owner
        get '/my_health/v2/medical_records/ccd/generate'
        get "/my_health/v2/medical_records/ccd/status/#{job_uuid}"

        VCR.use_cassette(success_cassette, match_requests_on: %i[method path]) do
          VCR.use_cassette(xml_cassette, match_requests_on: %i[method uri]) do
            get "#{download_path}.xml"
          end
        end

        expect(response).to have_http_status(:ok)
      end
    end

    context 'when successful with XML format' do
      let(:xml_cassette) { 'unified_health_data/get_ccd_s3_download_xml' }

      it 'fetches XML CCD from S3 using presigned URL from backend' do
        VCR.use_cassette(success_cassette, match_requests_on: %i[method path]) do
          VCR.use_cassette(xml_cassette, match_requests_on: %i[method uri]) do
            get "#{download_path}.xml"

            expect(response).to have_http_status(:ok)
            expect(response.headers['Content-Type']).to include('application/xml')
            expect(response.body).to include('ClinicalDocument')
          end
        end
      end
    end

    context 'when successful with HTML format' do
      let(:html_cassette) { 'unified_health_data/get_ccd_s3_download_html' }

      it 'fetches HTML CCD from S3 using presigned URL from backend' do
        VCR.use_cassette(success_cassette, match_requests_on: %i[method path]) do
          VCR.use_cassette(html_cassette, match_requests_on: %i[method uri]) do
            get "#{download_path}.html"

            expect(response).to have_http_status(:ok)
            expect(response.headers['Content-Type']).to include('text/html')
            expect(response.body).to include('<!DOCTYPE html')
          end
        end
      end
    end

    context 'when successful with PDF format' do
      let(:pdf_cassette) { 'unified_health_data/get_ccd_s3_download_pdf' }

      it 'fetches PDF CCD from S3 using presigned URL from backend' do
        VCR.use_cassette(success_cassette, match_requests_on: %i[method path]) do
          VCR.use_cassette(pdf_cassette, match_requests_on: %i[method uri]) do
            get "#{download_path}.pdf"

            expect(response).to have_http_status(:ok)
            expect(response.headers['Content-Type']).to include('application/pdf')
            expect(response.body).to start_with('%PDF')
          end
        end
      end
    end

    context 'when format is not specified' do
      let(:xml_cassette) { 'unified_health_data/get_ccd_s3_download_xml' }

      it 'defaults to XML format' do
        VCR.use_cassette(success_cassette, match_requests_on: %i[method path]) do
          VCR.use_cassette(xml_cassette, match_requests_on: %i[method uri]) do
            get download_path

            expect(response).to have_http_status(:ok)
            expect(response.headers['Content-Type']).to include('application/xml')
          end
        end
      end
    end

    context 'when presigned URL is nil (CCD not found)' do
      let(:service_double) { instance_double(UnifiedHealthData::CcdService) }

      before do
        allow(UnifiedHealthData::CcdService).to receive(:new).and_return(service_double)
        allow(service_double).to receive(:get_ccd_jobs).and_return(owned_ccd_jobs)
        allow(service_double).to receive(:get_ccd_url)
          .with(job_id:, format: 'xml').and_return(nil)
      end

      it 'returns 404 not found' do
        get download_path

        expect(response).to have_http_status(:not_found)
        json_response = JSON.parse(response.body)
        expect(json_response['errors'].first['title']).to eq('CCD Not Found')
        expect(json_response['errors'].first['status']).to eq(404)
      end
    end

    context 'when format is invalid' do
      it 'returns 404 due to routing constraints (never reaches controller)' do
        get "#{download_path}.json"

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when S3 URL is not on the allowlist' do
      let(:service_double) { instance_double(UnifiedHealthData::CcdService) }
      let(:disallowed_url) { 'https://evil-bucket.s3.amazonaws.com/malicious.xml' }

      before do
        allow(UnifiedHealthData::CcdService).to receive(:new).and_return(service_double)
        allow(service_double).to receive(:get_ccd_jobs).and_return(owned_ccd_jobs)
        allow(service_double).to receive(:get_ccd_url)
          .with(job_id:, format: 'xml').and_return(disallowed_url)
      end

      it 'returns 403 forbidden' do
        get download_path

        expect(response).to have_http_status(:forbidden)
        json_response = JSON.parse(response.body)
        expect(json_response['errors'].first['title']).to eq('Forbidden')
      end
    end

    context 'when S3 returns an error' do
      it 'passes through the upstream 403 status' do
        VCR.use_cassette(success_cassette, match_requests_on: %i[method path]) do
          stub_request(:get, s3_host_pattern)
            .to_return(status: 403, body: 'Access Denied')

          get download_path

          expect(response).to have_http_status(:forbidden)
        end
      end
    end

    context 'when the presigned URL is malformed' do
      let(:service_double) { instance_double(UnifiedHealthData::CcdService) }

      before do
        allow(UnifiedHealthData::CcdService).to receive(:new).and_return(service_double)
        allow(service_double).to receive(:get_ccd_jobs).and_return(owned_ccd_jobs)
        allow(service_double).to receive(:get_ccd_url)
          .with(job_id:, format: 'xml').and_return('https://exa mple.com/bad url')
      end

      it 'returns 400 bad request' do
        get download_path

        expect(response).to have_http_status(:bad_request)
        json_response = JSON.parse(response.body)
        expect(json_response['errors'].first['title']).to eq('Bad Request')
      end
    end

    context 'when service raises a client error' do
      let(:service_double) { instance_double(UnifiedHealthData::CcdService) }
      let(:client_error) do
        Common::Client::Errors::ClientError.new('SCDF service unavailable', 503)
      end

      before do
        allow(UnifiedHealthData::CcdService).to receive(:new).and_return(service_double)
        allow(service_double).to receive(:get_ccd_jobs).and_return(owned_ccd_jobs)
        allow(service_double).to receive(:get_ccd_url).and_raise(client_error)
      end

      it 'returns 502 bad gateway for upstream 5xx errors' do
        get download_path

        expect(response).to have_http_status(:bad_gateway)
        json_response = JSON.parse(response.body)
        expect(json_response['errors'].first['title']).to eq('S3 API Error')
      end
    end

    context 'when unexpected error occurs' do
      let(:service_double) { instance_double(UnifiedHealthData::CcdService) }

      before do
        allow(UnifiedHealthData::CcdService).to receive(:new).and_return(service_double)
        allow(service_double).to receive(:get_ccd_jobs).and_return(owned_ccd_jobs)
        allow(service_double).to receive(:get_ccd_url).and_raise(StandardError, 'Unexpected client error')
      end

      it 'returns 500 internal server error' do
        get download_path

        expect(response).to have_http_status(:internal_server_error)
        json_response = JSON.parse(response.body)
        expect(json_response['errors'].first['title']).to eq('Internal Server Error')
        expect(json_response['errors'].first['detail']).to include('unexpected error')
      end
    end

    context 'when the CCD job does not belong to the user' do
      before do
        allow_any_instance_of(UnifiedHealthData::CcdService)
          .to receive(:get_ccd_jobs)
          .and_return([UnifiedHealthData::Ccd.new(job_id: '99999', task_id: '99999')])
      end

      it 'returns 404 not found without fetching the document' do
        expect_any_instance_of(UnifiedHealthData::CcdService).not_to receive(:get_ccd_url)

        get download_path

        expect(response).to have_http_status(:not_found)
        json_response = JSON.parse(response.body)
        expect(json_response['errors'].first['title']).to eq('CCD Not Found')
        expect(json_response['errors'].first['detail']).to eq('The requested CCD is not available')
      end
    end

    context 'when the UUID job id belongs to another user' do
      let(:job_id) { 'b0733653-30b4-411f-a997-7453039e510c' }

      before do
        allow(Rails.cache).to receive(:read).and_call_original
        allow(Rails.cache).to receive(:read)
          .with("uhd:ccd_job_owner:#{job_id}").and_return('1999999999V999999')
      end

      it 'returns 404 not found without fetching the document' do
        expect_any_instance_of(UnifiedHealthData::CcdService).not_to receive(:get_ccd_url)

        get download_path

        expect(response).to have_http_status(:not_found)
        json_response = JSON.parse(response.body)
        expect(json_response['errors'].first['title']).to eq('CCD Not Found')
        expect(json_response['errors'].first['detail']).to eq('The requested CCD is not available')
      end
    end
  end
end
