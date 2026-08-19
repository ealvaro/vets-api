# frozen_string_literal: true

require 'rails_helper'
require 'unique_user_events'
require 'support/shared_contexts/uhd_security_endpoint'

RSpec.describe 'MyHealth::V2::ImmunizationsController', :skip_json_api_validation, type: :request do
  include_context 'uhd legacy security endpoint'

  let(:path) { '/my_health/v2/medical_records/immunizations' }
  let(:lh_immunizations_cassette) { 'lighthouse/veterans_health/get_immunizations' }
  let(:uhd_immunizations_cassette) { 'unified_health_data/get_immunizations_200' }
  let(:current_user) { build(:user, :mhv) }

  before do
    sign_in_as(current_user, stub_mhv_account: true)
  end

  describe 'GET /my_health/v2/medical_records/immunizations' do
    context 'with UHD data' do
      before do
        Timecop.freeze('2026-01-07T16:00:00Z')

        allow(UniqueUserEvents).to receive(:log_events)
      end

      after do
        Timecop.return
      end

      it 'tags the Datadog span with uhd data source' do
        span = spy('datadog_span')
        allow(Datadog::Tracing).to receive(:active_span).and_return(span)

        VCR.use_cassette(uhd_immunizations_cassette) do
          get path, headers: { 'X-Key-Inflection' => 'camel' }
        end

        expect(span).to have_received(:set_tag).with('medical_records.data_source', 'uhd')
      end

      context 'happy path' do
        before do
          VCR.use_cassette(uhd_immunizations_cassette) do
            get path, headers: { 'X-Key-Inflection' => 'camel' }
          end
        end

        it 'returns a successful response' do
          expect(response).to be_successful
          expect(response).to have_http_status(:ok)
          json_response = JSON.parse(response.body)
          expect(json_response['data'].count).to eq(4)
          expect(json_response['data']).to be_an(Array)
          expect(json_response['data'].first['type']).to eq('immunization')
          expect(json_response['data'].first).to include(
            'id',
            'type',
            'attributes'
          )
          expect(json_response['data'].first['attributes']).to include(
            'cvxCode',
            'date',
            'doseNumber',
            'doseSeries',
            'groupName',
            'location',
            'manufacturer',
            'note',
            'reaction',
            'shortDescription',
            'administrationSite',
            'lotNumber',
            'status'
          )
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

        it 'orders records by descending date, even if date format is different' do
          dates = response.parsed_body['data'].collect { |i| i['attributes']['date'] }
          expect(dates).to eq(['2025-12-12T18:00:00Z', '2025-12-10T14:19:00-06:00', '2023', '2016-04-04'])
        end

        it 'tracks metrics in StatsD with exact immunization count' do
          # First make a request to get the actual JSON response
          VCR.use_cassette(uhd_immunizations_cassette) do
            get path, headers: { 'X-Key-Inflection' => 'camel' }
          end

          # Get the actual count of immunizations returned
          json_response = JSON.parse(response.body)
          actual_count = json_response['data'].length

          # Now test that StatsD receives that exact count
          allow(StatsD).to receive(:gauge)
          expect(StatsD).to receive(:gauge).with('api.my_health.immunizations.count', actual_count)

          # Make the request again with the mock in place
          VCR.use_cassette(uhd_immunizations_cassette) do
            get path, headers: { 'X-Key-Inflection' => 'camel' }
          end
        end

        it 'includes location information in immunization data' do
          json_response = JSON.parse(response.body)

          # Verify that immunizations have location data
          expect(json_response['data']).to be_an(Array)
          expect(json_response['data']).not_to be_empty

          # Check that each immunization includes location data
          json_response['data'].each do |immunization|
            expect(immunization['attributes']).to have_key('location')
          end

          # Verify the location name for the first immunization
          expect(json_response['data'][0]['attributes']['location']).to eq('TEST')
        end
      end

      context 'partial failures' do
        it 'returns a successful partial response when one source fails' do
          allow(UniqueUserEvents).to receive(:log_events)
          VCR.use_cassette('unified_health_data/get_immunizations_206', match_requests_on: %i[method path]) do
            get path, headers: { 'X-Key-Inflection' => 'camel' }
          end
          expect(response).to be_successful
          expect(response).to have_http_status(:partial_content)
          json_response = JSON.parse(response.body)
          expect(json_response['meta']).to include('warnings')
          expect(json_response['meta']['warnings'][0]).to eq(
            {
              'severity' => 'warning',
              'code' => 'informational',
              'diagnostics' => 'Partial failure',
              'source' => 'oracle-health'
            }
          )
          expect(json_response['data']).to be_an(Array)
          expect(json_response['data'].first['type']).to eq('immunization')
          expect(json_response['data'].first).to include(
            'id',
            'type',
            'attributes'
          )
          expect(json_response['data'].first['attributes']).to include(
            'cvxCode',
            'date',
            'doseNumber',
            'doseSeries',
            'groupName',
            'location',
            'manufacturer',
            'note',
            'reaction',
            'shortDescription',
            'administrationSite',
            'lotNumber',
            'status'
          )
        end
      end

      context 'when response has no entries' do
        before do
          # Expect StatsD to receive count of 0
          allow(StatsD).to receive(:gauge)
          expect(StatsD).to receive(:gauge).with('api.my_health.immunizations.count', 0)

          VCR.use_cassette('unified_health_data/get_immunizations_no_records') do
            get path, headers: { 'X-Key-Inflection' => 'camel' }
          end
        end

        it 'returns a successful response' do
          expect(response).to be_successful
        end

        it 'returns an empty data array' do
          json_response = JSON.parse(response.body)
          expect(json_response['data']).to eq([])
        end
      end

      context 'error cases' do
        let(:mock_service) { instance_double(UnifiedHealthData::MedicalRecordsService) }

        before do
          allow_any_instance_of(MyHealth::V2::ImmunizationsController).to receive(:uhd_service).and_return(mock_service)
          allow(StatsD).to receive(:increment).and_call_original
        end

        context 'with client error' do
          before do
            allow(mock_service).to receive(:get_immunizations)
              .and_raise(Common::Client::Errors::ClientError.new(
                           'Internal server error', 500
                         ))

            get path, headers: { 'X-Key-Inflection' => 'camel' }
          end

          it 'returns bad_gateway status code' do
            expect(response).to have_http_status(:bad_gateway)
            expect(StatsD).to have_received(:increment).with('mhv_medical_records.client_error', anything)
          end

          it 'returns formatted error details' do
            json_response = JSON.parse(response.body)
            expect(json_response).to have_key('errors')
            expect(json_response['errors']).to be_an(Array)
            expect(json_response['errors'].first).to include(
              'title' => 'SCDF API Error',
              'detail' => 'Internal server error'
            )
          end
        end

        context 'with backend service exception' do
          before do
            allow(mock_service).to receive(:get_immunizations)
              .and_raise(Common::Exceptions::BackendServiceException.new('VA900',
                                                                         detail: 'Backend Service Unavailable'))

            get path, headers: { 'X-Key-Inflection' => 'camel' }
          end

          it 'returns bad_gateway status code' do
            expect(response).to have_http_status(:bad_gateway)
            expect(StatsD).to have_received(:increment).with('mhv_medical_records.backend_service_error', anything)
          end

          it 'includes error details in the response' do
            json_response = JSON.parse(response.body)
            expect(json_response).to have_key('errors')
          end
        end
      end
    end
  end

  describe 'GET /my_health/v2/medical_records/immunizations/:id' do
    let(:immunization_id) { '4-NsaRGtyJ4oKq' }
    let(:show_path) { "#{path}/#{immunization_id}" }

    context 'happy path' do
      before do
        VCR.use_cassette(lh_immunizations_cassette) do
          get show_path, headers: { 'X-Key-Inflection' => 'camel' }
        end
      end

      it 'returns a successful response' do
        expect(response).to be_successful
        json_response = JSON.parse(response.body)

        expect(json_response['data']).to be_a(Hash)
        expect(json_response['data']['id']).to eq(immunization_id)
        expect(json_response['data']['type']).to eq('immunization')
        expect(json_response['data']['attributes']).to have_key('location')
      end
    end

    context 'when immunization is not found in the bundle' do
      let(:mock_client) { instance_double(Lighthouse::VeteransHealth::Client) }
      let(:show_path) { "#{path}/non-existent-id" }

      before do
        allow_any_instance_of(MyHealth::V2::ImmunizationsController).to receive(:client).and_return(mock_client)
        allow(mock_client).to receive(:get_immunizations)
          .and_return(double('response', body: { 'entry' => [
                               { 'resource' => { 'id' => 'some-other-id', 'resourceType' => 'Immunization' } }
                             ] }))

        get show_path, headers: { 'X-Key-Inflection' => 'camel' }
      end

      it 'returns 404 not found' do
        expect(response).to have_http_status(:not_found)
      end

      it 'returns a formatted error payload' do
        json_response = JSON.parse(response.body)
        expect(json_response['errors']).to be_an(Array)
        expect(json_response['errors'].first).to include(
          'title' => 'Immunization Not Found',
          'detail' => 'The requested immunization record was not found',
          'code' => '404',
          'status' => 404
        )
      end
    end

    context 'error cases' do
      let(:mock_client) { instance_double(Lighthouse::VeteransHealth::Client) }

      before do
        allow_any_instance_of(MyHealth::V2::ImmunizationsController).to receive(:client).and_return(mock_client)
        allow(StatsD).to receive(:increment).and_call_original
      end

      context 'with client error' do
        before do
          allow(mock_client).to receive(:get_immunizations)
            .and_raise(Common::Client::Errors::ClientError.new('FHIR API Error', 500))

          get show_path, headers: { 'X-Key-Inflection' => 'camel' }
        end

        it 'returns bad_gateway status code' do
          expect(response).to have_http_status(:bad_gateway)
          expect(StatsD).to have_received(:increment).with('mhv_medical_records.client_error', anything)
        end

        it 'returns formatted error details' do
          json_response = JSON.parse(response.body)
          expect(json_response).to have_key('errors')
          expect(json_response['errors']).to be_an(Array)
          expect(json_response['errors'].first).to include(
            'title' => 'FHIR API Error',
            'detail' => 'FHIR API Error'
          )
        end
      end

      context 'with backend service exception' do
        before do
          allow(mock_client).to receive(:get_immunizations)
            .and_raise(Common::Exceptions::BackendServiceException.new('VA900', detail: 'Backend Service Unavailable'))

          get show_path, headers: { 'X-Key-Inflection' => 'camel' }
        end

        it 'returns bad_gateway status code' do
          expect(response).to have_http_status(:bad_gateway)
          expect(StatsD).to have_received(:increment).with('mhv_medical_records.backend_service_error', anything)
        end

        it 'includes error details in the response' do
          json_response = JSON.parse(response.body)
          expect(json_response).to have_key('errors')
        end
      end
    end
  end
end
