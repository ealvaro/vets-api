# frozen_string_literal: true

require_relative '../../../../support/helpers/rails_helper'
require_relative '../../../../support/helpers/committee_helper'
require 'unique_user_events'
require 'support/shared_contexts/uhd_security_endpoint'

RSpec.describe 'Mobile::V1::Health::Immunizations', :skip_json_api_validation, type: :request do
  include CommitteeHelper

  describe 'GET /mobile/v1/health/immunizations' do
    context 'UHD data retrieval' do
      include_context 'uhd legacy security endpoint'

      let!(:user) { sis_user(icn: '1000123456V123456') }
      let(:default_params) { { page: { size: 100 } } }

      before do
        Timecop.freeze(Time.zone.parse('2026-01-07T15:59:16Z'))
      end

      after { Timecop.return }

      it 'tags the Datadog span with uhd data source' do
        span = spy('datadog_span')
        allow(Datadog::Tracing).to receive(:active_span).and_return(span)

        VCR.use_cassette('unified_health_data/get_immunizations_200', match_requests_on: %i[method uri]) do
          get '/mobile/v1/health/immunizations', headers: sis_headers, params: default_params
        end

        expect(span).to have_received(:set_tag).with('medical_records.data_source', 'uhd')
      end

      context 'when the expected fields have data' do
        before do
          allow(UniqueUserEvents).to receive(:log_events)
          VCR.use_cassette('unified_health_data/get_immunizations_200', match_requests_on: %i[method uri]) do
            get '/mobile/v1/health/immunizations', headers: sis_headers, params: default_params
          end
        end

        it 'returns a 200 that matches the expected schema' do
          expect(response).to have_http_status(:ok)
          assert_schema_conform(200)
        end

        it 'logs unique user events for immunizations/vaccines accessed' do
          expect(UniqueUserEvents).to have_received(:log_events).with(
            user: anything,
            event_names: [
              UniqueUserEvents::EventRegistry::MEDICAL_RECORDS_ACCESSED,
              UniqueUserEvents::EventRegistry::MEDICAL_RECORDS_VACCINES_ACCESSED
            ]
          )
        end
      end

      context 'when entry is missing' do
        before do
          VCR.use_cassette('unified_health_data/get_immunizations_no_records',
                           match_requests_on: %i[method uri]) do
            get '/mobile/v1/health/immunizations', headers: sis_headers, params: nil
          end
        end

        it 'returns empty array and matches the expected schema' do
          expect(response).to have_http_status(:ok)
          assert_schema_conform(200)
          expect(response.parsed_body['data']).to eq([])
          expect(response.parsed_body['meta']['pagination']['totalEntries']).to eq(0)
        end
      end

      describe 'manufacturer population' do
        context 'when an immunization has a manufacturer provided' do
          it 'uses the vaccine manufacturer in the response' do
            VCR.use_cassette('unified_health_data/get_immunizations_200', match_requests_on: %i[method uri]) do
              get '/mobile/v1/health/immunizations', headers: sis_headers, params: default_params
            end
            vaccine_with_manufacturer_immunization = response.parsed_body['data'].select do |i|
              i['id'] == 'cde96bc7-fcc0-4bee-bcc0-c7f99515a83f'
            end

            expect(vaccine_with_manufacturer_immunization.dig(0, 'attributes')).to eq(
              { 'cvxCode' => 90_750,
                'date' => '2025-12-12T18:00:00Z',
                'doseNumber' => nil,
                'doseSeries' => nil,
                'groupName' => 'ZOSTER RECOMBINANT',
                'location' => 'TEST',
                'manufacturer' => 'GLAXOSMITHKLINE',
                'note' => nil,
                'provider' => 'MCGUIRE,MARCI P',
                'reaction' => nil,
                'shortDescription' => 'ZOSTER RECOMBINANT',
                'administrationSite' => 'RIGHT DELTOID',
                'lotNumber' => nil,
                'status' => 'completed' }
            )
          end
        end
      end

      describe 'pagination' do
        context 'when UHD is enabled' do
          it 'returns all records with hardcoded pagination meta', :aggregate_failures do
            VCR.use_cassette('unified_health_data/get_immunizations_200', match_requests_on: %i[method uri]) do
              get '/mobile/v1/health/immunizations', headers: sis_headers, params: nil
            end

            pagination = response.parsed_body['meta']['pagination']
            total_records = response.parsed_body['data'].length

            expect(pagination['currentPage']).to eq(1)
            expect(pagination['perPage']).to eq(5000)
            expect(pagination['totalPages']).to eq(1)
            expect(pagination['totalEntries']).to eq(total_records)
          end

          it 'ignores page params and returns all records', :aggregate_failures do
            VCR.use_cassette('unified_health_data/get_immunizations_200', match_requests_on: %i[method uri]) do
              get '/mobile/v1/health/immunizations', headers: sis_headers,
                                                     params: { page: { size: 2, number: 3 } }
            end

            pagination = response.parsed_body['meta']['pagination']
            total_records = response.parsed_body['data'].length

            expect(pagination['currentPage']).to eq(1)
            expect(pagination['totalEntries']).to eq(total_records)
          end
        end
      end

      describe 'record order' do
        it 'orders records by descending date' do
          VCR.use_cassette('unified_health_data/get_immunizations_200', match_requests_on: %i[method uri]) do
            get '/mobile/v1/health/immunizations', headers: sis_headers, params: default_params
          end

          dates = response.parsed_body['data'].collect { |i| i['attributes']['date'] }
          expect(dates).to eq(['2016-04-04', '2023', '2025-12-10T14:19:00-06:00', '2025-12-12T18:00:00Z'])
        end
      end

      context 'error handling via MedicalRecords::ErrorHandler' do
        let(:mock_service) { instance_double(UnifiedHealthData::MedicalRecordsService) }

        before do
          allow(Datadog::Tracing).to receive(:active_span).and_return(nil)
          allow(UnifiedHealthData::MedicalRecordsService).to receive(:new).and_return(mock_service)
        end

        shared_examples 'structured error response' do |expected_status, expected_attrs|
          it "returns #{expected_status} with structured error envelope" do
            get '/mobile/v1/health/immunizations', headers: sis_headers, params: default_params
            expect(response).to have_http_status(expected_status)
            error = JSON.parse(response.body)['errors']
            expect(error).to be_an(Array)
            expected_attrs.each { |key, val| expect(error.first[key].to_s).to include(val.to_s) }
          end
        end

        context 'when a GatewayTimeout error occurs' do
          before { allow(mock_service).to receive(:get_immunizations).and_raise(Common::Exceptions::GatewayTimeout) }

          include_examples 'structured error response', :gateway_timeout, { 'status' => '504' }
        end

        context 'when a Timeout::Error occurs' do
          before { allow(mock_service).to receive(:get_immunizations).and_raise(Timeout::Error, 'execution expired') }

          include_examples 'structured error response', :gateway_timeout, { 'title' => 'Gateway Timeout' }
        end

        context 'when a ClientError with status occurs' do
          before do
            allow(mock_service).to receive(:get_immunizations).and_raise(
              Common::Client::Errors::ClientError.new(nil, 502, { 'detail' => 'bad gateway' })
            )
          end

          include_examples 'structured error response', :bad_gateway,
                           { 'code' => '502', 'title' => 'Mobile UHD API Error' }
        end

        context 'when a ClientError without status occurs' do
          before do
            allow(mock_service).to receive(:get_immunizations).and_raise(
              Common::Client::Errors::ClientError.new(nil, nil)
            )
          end

          include_examples 'structured error response', :service_unavailable, { 'code' => '503' }
        end

        context 'when a Breakers::OutageException occurs' do
          before do
            breakers_service = instance_double(Breakers::Service, name: 'UHD')
            outage = instance_double(Breakers::Outage, start_time: Time.zone.now, end_time: nil,
                                                       service: breakers_service)
            allow(mock_service).to receive(:get_immunizations)
              .and_raise(Breakers::OutageException.new(outage, breakers_service))
          end

          include_examples 'structured error response', :service_unavailable, { 'title' => 'Service Unavailable' }
        end

        context 'when an unexpected StandardError occurs' do
          before do
            allow(mock_service).to receive(:get_immunizations).and_raise(StandardError, 'something went wrong')
          end

          it 'returns 500 with a safe generic message that does not leak the original error' do
            get '/mobile/v1/health/immunizations', headers: sis_headers, params: default_params
            expect(response).to have_http_status(:internal_server_error)
            detail = JSON.parse(response.body).dig('errors', 0, 'detail')
            expect(detail).to eq('An unexpected error occurred while retrieving Mobile immunizations.')
            expect(detail).not_to include('something went wrong')
          end
        end

        context 'when a NotImplemented error occurs' do
          before do
            allow(mock_service).to receive(:get_immunizations).and_raise(Common::Exceptions::NotImplemented)
          end

          it 're-raises and is not swallowed by handle_error' do
            get '/mobile/v1/health/immunizations', headers: sis_headers, params: default_params
            expect(response).to have_http_status(:not_implemented)
          end
        end
      end
    end
  end
end
