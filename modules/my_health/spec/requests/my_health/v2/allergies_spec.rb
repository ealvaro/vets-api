# frozen_string_literal: true

require 'rails_helper'
require 'support/mr_client_helpers'
require 'medical_records/client'
require 'medical_records/bb_internal/client'
require 'support/shared_examples_for_mhv'
require 'unified_health_data/medical_records_service'
require 'unique_user_events'
require 'support/shared_contexts/uhd_security_endpoint'

RSpec.describe 'MyHealth::V2::AllergiesController', :skip_json_api_validation, type: :request do
  include_context 'uhd legacy security endpoint'

  let(:user_id) { '11898795' }
  let(:default_params) { { start_date: '2024-01-01', end_date: '2025-05-31' } }
  let(:path) { '/my_health/v2/medical_records/allergies' }

  let(:uhd_flipper) { :mhv_accelerated_delivery_uhd_enabled }

  let(:va_patient) { true }
  let(:current_user) { build(:user, :mhv) }

  before do
    Timecop.freeze('2025-06-02T08:00:00Z')
    sign_in_as(current_user, stub_mhv_account: true)
    allow(Flipper).to receive(:enabled?).with(uhd_flipper, instance_of(User)).and_return(true)
  end

  after do
    Timecop.return
  end

  describe 'GET /my_health/v2/medical_records/allergies#index' do
    context 'no_cache parameter' do
      it 'passes no_cache: true to the service when no_cache param is present' do
        allow(UniqueUserEvents).to receive(:log_events)
        expect_any_instance_of(UnifiedHealthData::MedicalRecordsService)
          .to receive(:get_allergies).with(no_cache: true).and_call_original
        VCR.use_cassette('unified_health_data/get_allergies_200', match_requests_on: %i[method path]) do
          get '/my_health/v2/medical_records/allergies',
              params: { no_cache: true },
              headers: { 'X-Key-Inflection' => 'camel' }
        end
        expect(response).to be_successful
      end

      it 'passes no_cache: false to the service when no_cache param is absent' do
        allow(UniqueUserEvents).to receive(:log_events)
        expect_any_instance_of(UnifiedHealthData::MedicalRecordsService)
          .to receive(:get_allergies).with(no_cache: false).and_call_original
        VCR.use_cassette('unified_health_data/get_allergies_200', match_requests_on: %i[method path]) do
          get '/my_health/v2/medical_records/allergies',
              headers: { 'X-Key-Inflection' => 'camel' }
        end
        expect(response).to be_successful
      end

      it 'passes no_cache: false to the service when no_cache param is "false"' do
        allow(UniqueUserEvents).to receive(:log_events)
        expect_any_instance_of(UnifiedHealthData::MedicalRecordsService)
          .to receive(:get_allergies).with(no_cache: false).and_call_original
        VCR.use_cassette('unified_health_data/get_allergies_200', match_requests_on: %i[method path]) do
          get '/my_health/v2/medical_records/allergies',
              params: { no_cache: 'false' },
              headers: { 'X-Key-Inflection' => 'camel' }
        end
        expect(response).to be_successful
      end
    end

    context 'happy path' do
      it 'returns a successful response' do
        allow(UniqueUserEvents).to receive(:log_events)
        VCR.use_cassette('unified_health_data/get_allergies_200', match_requests_on: %i[method path]) do
          get '/my_health/v2/medical_records/allergies', headers: { 'X-Key-Inflection' => 'camel' }
        end
        expect(response).to be_successful
        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        # Cassette contains 13 AllergyIntolerance resources total, but only 10 have 'active' clinicalStatus
        # Filtered out: VistA ASPIRIN (no status), OH Grass (resolved), OH Cashews (no status)
        expect(json_response['data'].count).to eq(10)
        expect(json_response['data']).to be_an(Array)
        expect(json_response['data'].first['type']).to eq('allergy')
        expect(json_response['data'].first).to include(
          'id',
          'type',
          'attributes'
        )
        expect(json_response['data'].first['attributes']).to include(
          'id',
          'name',
          'date',
          'reactions',
          'categories',
          'location',
          'observedHistoric',
          'notes',
          'provider'
        )

        # Verify event logging was called
        expect(UniqueUserEvents).to have_received(:log_events).with(
          user: anything,
          event_names: [
            UniqueUserEvents::EventRegistry::MEDICAL_RECORDS_ACCESSED,
            UniqueUserEvents::EventRegistry::MEDICAL_RECORDS_ALLERGIES_ACCESSED
          ]
        )
      end

      it 'filters out allergies without active clinicalStatus from both VistA and Oracle Health' do
        VCR.use_cassette('unified_health_data/get_allergies_200', match_requests_on: %i[method path]) do
          get '/my_health/v2/medical_records/allergies', headers: { 'X-Key-Inflection' => 'camel' }
        end
        expect(response).to be_successful
        json_response = JSON.parse(response.body)

        # Verify that non-active allergies are not included in the response
        # VistA: ASPIRIN (id: 2676, no clinicalStatus)
        # Oracle Health: Grass (id: 132312405, resolved), Cashews (id: 132316427, no clinicalStatus)
        allergy_ids = json_response['data'].map { |a| a['id'] }
        expect(allergy_ids).not_to include('2676')       # VistA no clinicalStatus
        expect(allergy_ids).not_to include('132312405')  # Oracle Health resolved
        expect(allergy_ids).not_to include('132316427')  # Oracle Health no clinicalStatus
      end

      it 'returns a successful response with an empty data array' do
        VCR.use_cassette('unified_health_data/get_allergies_no_records', match_requests_on: %i[method path]) do
          get '/my_health/v2/medical_records/allergies',
              headers: { 'X-Key-Inflection' => 'camel' }
        end
        expect(response).to be_successful
        json_response = JSON.parse(response.body)

        expect(json_response['data']).to eq([])
      end
    end

    context 'partial failures' do
      it 'returns a successful partial response when one source fails' do
        allow(UniqueUserEvents).to receive(:log_events)
        VCR.use_cassette('unified_health_data/get_allergies_206', match_requests_on: %i[method path]) do
          get '/my_health/v2/medical_records/allergies', headers: { 'X-Key-Inflection' => 'camel' }
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
        expect(json_response['data'].first['type']).to eq('allergy')
        expect(json_response['data'].first).to include(
          'id',
          'type',
          'attributes'
        )
        expect(json_response['data'].first['attributes']).to include(
          'id',
          'name',
          'date',
          'reactions',
          'categories',
          'location',
          'observedHistoric',
          'notes',
          'provider'
        )
      end
    end

    context 'with API gateway security endpoint enabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:mhv_uhd_api_gateway_security_endpoint).and_return(true)
      end

      it 'returns a successful response using the gateway security path' do
        VCR.use_cassette('unified_health_data/get_allergies_200_api_gateway',
                         match_requests_on: %i[method path]) do
          get '/my_health/v2/medical_records/allergies', headers: { 'X-Key-Inflection' => 'camel' }
        end
        expect(response).to be_successful
        json_response = JSON.parse(response.body)
        expect(json_response['data'].count).to eq(10)
        expect(json_response['data'].first['type']).to eq('allergy')
      end

      it 'returns a successful response with an empty data array using the gateway security path' do
        VCR.use_cassette('unified_health_data/get_allergies_no_records_api_gateway',
                         match_requests_on: %i[method path]) do
          get '/my_health/v2/medical_records/allergies', headers: { 'X-Key-Inflection' => 'camel' }
        end
        expect(response).to be_successful
        json_response = JSON.parse(response.body)
        expect(json_response['data']).to eq([])
      end
    end

    context 'error responses' do
      before { allow(StatsD).to receive(:increment).and_call_original }

      it 'returns a 500 response when there is a server error' do
        allow_any_instance_of(UnifiedHealthData::MedicalRecordsService).to receive(:get_allergies)
          .and_raise(Common::Exceptions::InternalServerError.new(Faraday::ServerError.new))
        # This cassette doesn't matter since we're stubbing the service call to raise an error
        VCR.use_cassette('unified_health_data/get_allergies_200') do
          get '/my_health/v2/medical_records/allergies',
              headers: { 'X-Key-Inflection' => 'camel' }
        end
        expect(response).to have_http_status(:internal_server_error)
        expect(StatsD).to have_received(:increment).with('mhv_medical_records.unexpected_error', anything)
      end

      it 'returns an error response when there is a client error' do
        allow_any_instance_of(UnifiedHealthData::MedicalRecordsService).to receive(:get_allergies)
          .and_raise(Common::Client::Errors::ClientError.new('Internal Server Error', 500))
        # This cassette doesn't matter since we're stubbing the service call to raise an error
        VCR.use_cassette('unified_health_data/get_allergies_200') do
          get '/my_health/v2/medical_records/allergies',
              headers: { 'X-Key-Inflection' => 'camel' }
        end

        expect(response).to have_http_status(:bad_gateway)
        expect(StatsD).to have_received(:increment).with('mhv_medical_records.client_error', anything)
      end

      it 'returns 502 when UpstreamPartialFailure is raised' do
        allow_any_instance_of(UnifiedHealthData::MedicalRecordsService).to receive(:get_allergies)
          .and_raise(Common::Exceptions::UpstreamPartialFailure.new(
                       failed_sources: ['vista'],
                       failure_details: [{ source: 'vista', code: 'exception',
                                           diagnostics: '502 Bad Gateway' }]
                     ))
        VCR.use_cassette('unified_health_data/get_allergies_200') do
          get '/my_health/v2/medical_records/allergies',
              headers: { 'X-Key-Inflection' => 'camel' }
        end
        expect(response).to have_http_status(:bad_gateway)
        json_response = JSON.parse(response.body)
        expect(json_response['errors'].first['code']).to eq('502')
        expect(json_response['errors'].first['detail']).to include('vista')
      end
    end

    context 'recoverable partial failures' do
      let(:recoverable_warnings) do
        [
          { source: 'oracle-health', code: 'exception', severity: 'error',
            diagnostics: '502 Bad Gateway' },
          { source: 'oracle-health', code: 'incomplete', severity: 'error',
            diagnostics: 'Response is incomplete due to source outage' }
        ]
      end

      let(:partial_allergy) do
        UnifiedHealthData::Allergy.new(
          id: '123', name: 'Penicillin', date: '2024-06-01',
          categories: ['medication'], reactions: [], notes: []
        )
      end

      context 'when flag is ON and single source is recoverable' do
        before do
          allow(Flipper).to receive(:enabled?)
            .with(:mhv_medical_records_partial_failure_handling).and_return(true)
          allow(UniqueUserEvents).to receive(:log_events)
          allow_any_instance_of(UnifiedHealthData::MedicalRecordsService).to receive(:get_allergies)
            .and_return({ records: [partial_allergy], warnings: recoverable_warnings })
        end

        it 'returns 206 with partial records and warnings in meta' do
          get '/my_health/v2/medical_records/allergies', headers: { 'X-Key-Inflection' => 'camel' }

          expect(response).to have_http_status(:partial_content)
          json_response = JSON.parse(response.body)
          expect(json_response['data']).to be_an(Array)
          expect(json_response['data'].size).to eq(1)
          expect(json_response['data'].first['attributes']['name']).to eq('Penicillin')
          expect(json_response['meta']['warnings']).to be_an(Array)
          expect(json_response['meta']['warnings'].size).to eq(2)
        end
      end

      context 'when flag is ON and failure is not recoverable' do
        before do
          allow(Flipper).to receive(:enabled?)
            .with(:mhv_medical_records_partial_failure_handling).and_return(true)
          error = Common::Exceptions::UpstreamPartialFailure.new(
            failed_sources: ['oracle-health'],
            failure_details: [{ source: 'oracle-health', code: 'exception',
                                diagnostics: 'Data validation failure' }]
          )
          allow_any_instance_of(UnifiedHealthData::MedicalRecordsService).to receive(:get_allergies).and_raise(error)
        end

        it 'returns 502' do
          VCR.use_cassette('unified_health_data/get_allergies_200') do
            get '/my_health/v2/medical_records/allergies',
                headers: { 'X-Key-Inflection' => 'camel' }
          end
          expect(response).to have_http_status(:bad_gateway)
        end
      end

      context 'when flag is ON and both sources are recoverable (all failed)' do
        before do
          allow(Flipper).to receive(:enabled?)
            .with(:mhv_medical_records_partial_failure_handling).and_return(true)
          error = Common::Exceptions::UpstreamPartialFailure.new(
            failed_sources: %w[vista oracle-health],
            failure_details: [
              { source: 'vista', code: 'incomplete', diagnostics: 'Incomplete' },
              { source: 'oracle-health', code: 'incomplete', diagnostics: 'Incomplete' }
            ]
          )
          allow_any_instance_of(UnifiedHealthData::MedicalRecordsService).to receive(:get_allergies).and_raise(error)
        end

        it 'returns 502' do
          VCR.use_cassette('unified_health_data/get_allergies_200') do
            get '/my_health/v2/medical_records/allergies',
                headers: { 'X-Key-Inflection' => 'camel' }
          end
          expect(response).to have_http_status(:bad_gateway)
        end
      end

      context 'when flag is OFF' do
        before do
          allow(Flipper).to receive(:enabled?)
            .with(:mhv_medical_records_partial_failure_handling).and_return(false)
          error = Common::Exceptions::UpstreamPartialFailure.new(
            failed_sources: ['vista'],
            failure_details: [{ source: 'vista', code: 'exception',
                                diagnostics: '502 Bad Gateway' }]
          )
          allow_any_instance_of(UnifiedHealthData::MedicalRecordsService).to receive(:get_allergies).and_raise(error)
        end

        it 'returns 502 (not 500)' do
          VCR.use_cassette('unified_health_data/get_allergies_200') do
            get '/my_health/v2/medical_records/allergies',
                headers: { 'X-Key-Inflection' => 'camel' }
          end
          expect(response).to have_http_status(:bad_gateway)
        end
      end
    end

    context 'recoverable partial failures (VCR integration)' do
      context 'when flag is ON and single source has incomplete signal' do
        before do
          allow(Flipper).to receive(:enabled?)
            .with(:mhv_medical_records_partial_failure_handling).and_return(true)
          allow(UniqueUserEvents).to receive(:log_events)
        end

        it 'returns 206 with VistA records and warnings from oracle-health' do
          VCR.use_cassette('unified_health_data/get_allergies_recoverable_partial_failure',
                           match_requests_on: %i[method path]) do
            get '/my_health/v2/medical_records/allergies', headers: { 'X-Key-Inflection' => 'camel' }
          end

          expect(response).to have_http_status(:partial_content)
          json_response = JSON.parse(response.body)
          expect(json_response['data']).to be_an(Array)
          expect(json_response['data'].size).to eq(1)
          expect(json_response['data'].first['attributes']['name']).to eq('TRAZODONE')
          expect(json_response['meta']['warnings']).to be_an(Array)
          expect(json_response['meta']['warnings'].size).to be >= 1
        end
      end

      context 'when flag is ON and all sources have incomplete signal' do
        before do
          allow(Flipper).to receive(:enabled?)
            .with(:mhv_medical_records_partial_failure_handling).and_return(true)
        end

        it 'returns 502 because all sources failed' do
          VCR.use_cassette('unified_health_data/get_allergies_all_sources_recoverable_failure',
                           match_requests_on: %i[method path]) do
            get '/my_health/v2/medical_records/allergies', headers: { 'X-Key-Inflection' => 'camel' }
          end

          expect(response).to have_http_status(:bad_gateway)
          json_response = JSON.parse(response.body)
          expect(json_response['errors']).to be_an(Array)
          expect(json_response['errors'].first['code']).to eq('502')
        end
      end

      context 'when flag is OFF and single source has incomplete signal' do
        before do
          allow(Flipper).to receive(:enabled?)
            .with(:mhv_medical_records_partial_failure_handling).and_return(false)
        end

        it 'returns 502 because flag is off (falls through to raise)' do
          VCR.use_cassette('unified_health_data/get_allergies_recoverable_partial_failure',
                           match_requests_on: %i[method path]) do
            get '/my_health/v2/medical_records/allergies', headers: { 'X-Key-Inflection' => 'camel' }
          end

          expect(response).to have_http_status(:bad_gateway)
        end
      end
    end
  end

  describe 'GET /my_health/v2/medical_records/allergies#show' do
    context 'happy path' do
      it 'returns a successful response for a single allergy' do
        VCR.use_cassette('unified_health_data/get_allergies_200', match_requests_on: %i[method path]) do
          get '/my_health/v2/medical_records/allergies/2677', headers: { 'X-Key-Inflection' => 'camel' }
        end
        expect(response).to be_successful
        json_response = JSON.parse(response.body)
        expect(json_response['data']['type']).to eq('allergy')
        expect(json_response['data']).to include(
          'id',
          'type',
          'attributes'
        )
        expect(json_response['data']['attributes']).to include(
          'id',
          'name',
          'date',
          'reactions',
          'categories',
          'location',
          'observedHistoric',
          'notes',
          'provider'
        )
      end

      # TODO: Probably this should return a 404? Maybe?
      it 'returns a 404 not found' do
        VCR.use_cassette('unified_health_data/get_allergies_no_records', match_requests_on: %i[method path]) do
          get '/my_health/v2/medical_records/allergies/12345',
              headers: { 'X-Key-Inflection' => 'camel' }
        end
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'with API gateway security endpoint enabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:mhv_uhd_api_gateway_security_endpoint).and_return(true)
      end

      it 'returns a successful response for a single allergy using the gateway security path' do
        VCR.use_cassette('unified_health_data/get_allergies_200_api_gateway',
                         match_requests_on: %i[method path]) do
          get '/my_health/v2/medical_records/allergies/2677', headers: { 'X-Key-Inflection' => 'camel' }
        end
        expect(response).to be_successful
        json_response = JSON.parse(response.body)
        expect(json_response['data']['type']).to eq('allergy')
        expect(json_response['data']['attributes']).to include('id', 'name', 'reactions')
      end

      it 'returns a 404 not found using the gateway security path' do
        VCR.use_cassette('unified_health_data/get_allergies_no_records_api_gateway',
                         match_requests_on: %i[method path]) do
          get '/my_health/v2/medical_records/allergies/12345',
              headers: { 'X-Key-Inflection' => 'camel' }
        end
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'error responses' do
      it 'returns a 500 response when there is a server error' do
        allow_any_instance_of(UnifiedHealthData::MedicalRecordsService).to receive(:get_single_allergy)
          .and_raise(Common::Exceptions::InternalServerError.new(Faraday::ServerError.new))
        # This cassette doesn't matter since we're stubbing the service call to raise an error
        VCR.use_cassette('unified_health_data/get_allergies_200') do
          get '/my_health/v2/medical_records/allergies/12345',
              headers: { 'X-Key-Inflection' => 'camel' }
        end
        expect(response).to have_http_status(:internal_server_error)
      end

      it 'returns an error response when there is a client error' do
        allow_any_instance_of(UnifiedHealthData::MedicalRecordsService).to receive(:get_single_allergy)
          .and_raise(Common::Client::Errors::ClientError.new(Faraday::ClientError.new))
        # This cassette doesn't matter since we're stubbing the service call to raise an error
        VCR.use_cassette('unified_health_data/get_allergies_200') do
          get '/my_health/v2/medical_records/allergies/12345',
              headers: { 'X-Key-Inflection' => 'camel' }
        end
        expect(response).to have_http_status(:service_unavailable)
      end
    end
  end
end
