# frozen_string_literal: true

require 'rails_helper'
require 'unified_health_data/client'

RSpec.describe UnifiedHealthData::Client do
  subject(:client) { described_class.new }

  describe '#check_for_operation_outcomes!' do
    let(:success_body) do
      {
        'vista' => {
          'entry' => [
            { 'resource' => { 'resourceType' => 'AllergyIntolerance', 'id' => '123' } }
          ]
        },
        'oracle-health' => {
          'entry' => [
            { 'resource' => { 'resourceType' => 'AllergyIntolerance', 'id' => '456' } }
          ]
        }
      }
    end

    let(:partial_failure_body) do
      {
        'vista' => {
          'entry' => [
            { 'resource' => { 'resourceType' => 'AllergyIntolerance', 'id' => '123' } }
          ]
        },
        'oracle-health' => {
          'entry' => [
            {
              'resource' => {
                'resourceType' => 'OperationOutcome',
                'issue' => [
                  {
                    'severity' => 'error',
                    'code' => 'exception',
                    'diagnostics' => 'Exhausted retry attempts for Oracle Health - giving up'
                  }
                ]
              }
            }
          ]
        }
      }
    end

    context 'when SCDF returns success response' do
      let(:success_response) { build_faraday_response(success_body) }

      it 'does not raise an exception' do
        expect do
          client.send(:check_for_operation_outcomes!, success_response, '/uhd/v1/allergies?patientId=123')
        end.not_to raise_error
      end
    end

    context 'when SCDF returns OperationOutcome with error severity' do
      let(:partial_failure_response) { build_faraday_response(partial_failure_body) }

      before do
        allow(Rails.logger).to receive(:warn)
        allow(StatsD).to receive(:increment)
      end

      it 'raises UpstreamPartialFailure exception' do
        expect do
          client.send(:check_for_operation_outcomes!, partial_failure_response, '/uhd/v1/allergies?patientId=123')
        end.to raise_error(Common::Exceptions::UpstreamPartialFailure)
      end

      it 'includes failed_sources in the exception' do
        client.send(:check_for_operation_outcomes!, partial_failure_response, '/uhd/v1/allergies?patientId=123')
      rescue Common::Exceptions::UpstreamPartialFailure => e
        expect(e.failed_sources).to eq(['oracle-health'])
      end

      it 'logs the partial failure' do
        begin
          client.send(:check_for_operation_outcomes!, partial_failure_response, '/uhd/v1/allergies?patientId=123')
        rescue Common::Exceptions::UpstreamPartialFailure
          # expected
        end

        expect(Rails.logger).to have_received(:warn).with(
          hash_including(
            message: 'UHD upstream source returned OperationOutcome error',
            failed_sources: ['oracle-health'],
            resource_type: 'allergies'
          )
        )
      end

      it 'increments StatsD counter' do
        begin
          client.send(:check_for_operation_outcomes!, partial_failure_response, '/uhd/v1/allergies?patientId=123')
        rescue Common::Exceptions::UpstreamPartialFailure
          # expected
        end

        expect(StatsD).to have_received(:increment).with(
          'api.uhd.partial_failure',
          tags: ['source:oracle-health', 'resource_type:allergies']
        )
      end
    end

    context 'when OperationOutcome has warning severity (not error)' do
      let(:warning_body) do
        {
          'vista' => { 'entry' => [] },
          'oracle-health' => {
            'entry' => [
              {
                'resource' => {
                  'resourceType' => 'OperationOutcome',
                  'issue' => [{ 'severity' => 'warning', 'code' => 'informational' }]
                }
              }
            ]
          }
        }
      end
      let(:warning_response) { build_faraday_response(warning_body) }

      before do
        allow(Rails.logger).to receive(:warn)
        allow(StatsD).to receive(:increment)
      end

      it 'does not raise an exception' do
        expect do
          client.send(:check_for_operation_outcomes!, warning_response, '/uhd/v1/allergies?patientId=123')
        end.not_to raise_error
      end

      it 'injects _warnings into the response body' do
        client.send(:check_for_operation_outcomes!, warning_response, '/uhd/v1/allergies?patientId=123')
        expect(warning_response.body['_warnings']).to be_an(Array)
        expect(warning_response.body['_warnings'].size).to eq(1)
        expect(warning_response.body['_warnings'].first).to include(source: 'oracle-health', severity: 'warning')
      end

      it 'logs the warning and increments StatsD' do
        client.send(:check_for_operation_outcomes!, warning_response, '/uhd/v1/allergies?patientId=123')

        expect(Rails.logger).to have_received(:warn).with(
          hash_including(message: 'UHD upstream source returned OperationOutcome warning', resource_type: 'allergies')
        )
        expect(StatsD).to have_received(:increment).with(
          'api.uhd.partial_warning',
          tags: ['source:oracle-health', 'resource_type:allergies']
        )
      end
    end

    context 'when response body is not a Hash (non-FHIR response)' do
      let(:array_response) { build_faraday_response([{ 'success' => true }]) }

      it 'does not raise an exception' do
        # Detector only parses when body.is_a?(Hash), so array bodies are skipped entirely
        expect do
          client.send(:check_for_operation_outcomes!, array_response, '/uhd/v1/refill')
        end.not_to raise_error
      end
    end

    context 'when response lacks vista/oracle-health keys' do
      let(:non_scdf_body) do
        {
          'resourceType' => 'OperationOutcome',
          'issue' => [{ 'severity' => 'error', 'code' => 'exception' }]
        }
      end
      let(:response) { build_faraday_response(non_scdf_body) }

      it 'does not raise an exception' do
        # Detector looks for body['vista'] and body['oracle-health'], finds neither
        expect do
          client.send(:check_for_operation_outcomes!, response, '/some/unknown/path')
        end.not_to raise_error
      end
    end

    context 'when feature flag is ON and single source is recoverable (has incomplete)' do
      let(:recoverable_body) do
        {
          'vista' => {
            'entry' => [
              { 'resource' => { 'resourceType' => 'AllergyIntolerance', 'id' => '123' } }
            ]
          },
          'oracle-health' => {
            'entry' => [
              {
                'resource' => {
                  'resourceType' => 'OperationOutcome',
                  'issue' => [
                    { 'severity' => 'error', 'code' => 'exception',
                      'diagnostics' => '502 Bad Gateway' },
                    { 'severity' => 'error', 'code' => 'incomplete',
                      'diagnostics' => 'Response is incomplete due to source outage' }
                  ]
                }
              }
            ]
          }
        }
      end
      let(:response) { build_faraday_response(recoverable_body) }

      before do
        allow(Flipper).to receive(:enabled?).with(:mhv_medical_records_partial_failure_handling).and_return(true)
        allow(Rails.logger).to receive(:warn)
        allow(StatsD).to receive(:increment)
      end

      it 'does not raise an exception' do
        expect do
          client.send(:check_for_operation_outcomes!, response, '/uhd/v1/allergies?patientId=123')
        end.not_to raise_error
      end

      it 'injects failure_details as _warnings into the response body' do
        client.send(:check_for_operation_outcomes!, response, '/uhd/v1/allergies?patientId=123')
        expect(response.body['_warnings']).to be_an(Array)
        expect(response.body['_warnings']).to include(
          hash_including(source: 'oracle-health', code: 'exception'),
          hash_including(source: 'oracle-health', code: 'incomplete')
        )
      end

      it 'still logs and tracks metrics' do
        client.send(:check_for_operation_outcomes!, response, '/uhd/v1/allergies?patientId=123')

        expect(Rails.logger).to have_received(:warn).with(
          hash_including(message: 'UHD upstream source returned OperationOutcome error')
        )
        expect(StatsD).to have_received(:increment).with(
          'api.uhd.partial_failure',
          tags: ['source:oracle-health', 'resource_type:allergies']
        )
      end
    end

    context 'when feature flag is ON and single source is NOT recoverable (no incomplete code)' do
      let(:non_recoverable_body) do
        {
          'vista' => {
            'entry' => [
              { 'resource' => { 'resourceType' => 'AllergyIntolerance', 'id' => '123' } }
            ]
          },
          'oracle-health' => {
            'entry' => [
              {
                'resource' => {
                  'resourceType' => 'OperationOutcome',
                  'issue' => [
                    { 'severity' => 'error', 'code' => 'exception',
                      'diagnostics' => 'Data validation failure' }
                  ]
                }
              }
            ]
          }
        }
      end
      let(:response) { build_faraday_response(non_recoverable_body) }

      before do
        allow(Flipper).to receive(:enabled?).with(:mhv_medical_records_partial_failure_handling).and_return(true)
        allow(Rails.logger).to receive(:warn)
        allow(StatsD).to receive(:increment)
      end

      it 'raises UpstreamPartialFailure' do
        expect do
          client.send(:check_for_operation_outcomes!, response, '/uhd/v1/allergies?patientId=123')
        end.to raise_error(Common::Exceptions::UpstreamPartialFailure)
      end
    end

    context 'when feature flag is ON and both sources are recoverable' do
      let(:both_failed_body) do
        {
          'vista' => {
            'entry' => [
              {
                'resource' => {
                  'resourceType' => 'OperationOutcome',
                  'issue' => [
                    { 'severity' => 'error', 'code' => 'exception', 'diagnostics' => 'VistA timeout' },
                    { 'severity' => 'error', 'code' => 'incomplete', 'diagnostics' => 'Incomplete' }
                  ]
                }
              }
            ]
          },
          'oracle-health' => {
            'entry' => [
              {
                'resource' => {
                  'resourceType' => 'OperationOutcome',
                  'issue' => [
                    { 'severity' => 'error', 'code' => 'exception', 'diagnostics' => 'OH timeout' },
                    { 'severity' => 'error', 'code' => 'incomplete', 'diagnostics' => 'Incomplete' }
                  ]
                }
              }
            ]
          }
        }
      end
      let(:response) { build_faraday_response(both_failed_body) }

      before do
        allow(Flipper).to receive(:enabled?).with(:mhv_medical_records_partial_failure_handling).and_return(true)
        allow(Rails.logger).to receive(:warn)
        allow(StatsD).to receive(:increment)
      end

      it 'raises UpstreamPartialFailure because all sources failed' do
        expect do
          client.send(:check_for_operation_outcomes!, response, '/uhd/v1/allergies?patientId=123')
        end.to raise_error(Common::Exceptions::UpstreamPartialFailure)
      end
    end

    context 'when feature flag is OFF and single source is recoverable' do
      let(:recoverable_body) do
        {
          'vista' => {
            'entry' => [
              { 'resource' => { 'resourceType' => 'AllergyIntolerance', 'id' => '123' } }
            ]
          },
          'oracle-health' => {
            'entry' => [
              {
                'resource' => {
                  'resourceType' => 'OperationOutcome',
                  'issue' => [
                    { 'severity' => 'error', 'code' => 'exception',
                      'diagnostics' => '502 Bad Gateway' },
                    { 'severity' => 'error', 'code' => 'incomplete',
                      'diagnostics' => 'Response is incomplete due to source outage' }
                  ]
                }
              }
            ]
          }
        }
      end
      let(:response) { build_faraday_response(recoverable_body) }

      before do
        allow(Flipper).to receive(:enabled?).with(:mhv_medical_records_partial_failure_handling).and_return(false)
        allow(Rails.logger).to receive(:warn)
        allow(StatsD).to receive(:increment)
      end

      it 'raises UpstreamPartialFailure (existing behavior preserved)' do
        expect do
          client.send(:check_for_operation_outcomes!, response, '/uhd/v1/allergies?patientId=123')
        end.to raise_error(Common::Exceptions::UpstreamPartialFailure)
      end
    end
  end

  describe '#fetch_access_token' do
    let(:host) { Settings.mhv.uhd.host }
    let(:legacy_security_url) { "#{Settings.mhv.uhd.security_host}/mhvapi/security/v1/login" }
    let(:gateway_security_url) { "#{Settings.mhv.api_gateway.hosts.security}/v1/security/login" }

    context 'when mhv_uhd_api_gateway_security_endpoint is disabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:mhv_uhd_api_gateway_security_endpoint).and_return(false)
        stub_request(:post, legacy_security_url)
          .to_return(status: 200, headers: { 'authorization' => 'Bearer legacy-token' })
        stub_request(:get, %r{#{Regexp.escape(host)}/v1/medicalrecords/})
          .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })
      end

      it 'posts to the legacy security host' do
        client.get_allergies_by_date(patient_id: '123', start_date: '2024-01-01', end_date: '2025-01-01')

        expect(WebMock).to have_requested(:post, legacy_security_url)
      end

      it 'does not send x-api-key header on the login request' do
        client.get_allergies_by_date(patient_id: '123', start_date: '2024-01-01', end_date: '2025-01-01')

        expect(WebMock).to have_requested(:post, legacy_security_url)
          .with { |req| req.headers.keys.none? { |k| k.casecmp('x-api-key').zero? } }
      end

      it 'reads the authorization header from the login response' do
        client.get_allergies_by_date(patient_id: '123', start_date: '2024-01-01', end_date: '2025-01-01')

        expect(WebMock).to have_requested(:get, %r{#{Regexp.escape(host)}/v1/medicalrecords/allergies})
          .with(headers: { 'Authorization' => 'Bearer legacy-token' })
      end
    end

    context 'when mhv_uhd_api_gateway_security_endpoint is enabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:mhv_uhd_api_gateway_security_endpoint).and_return(true)
        stub_request(:post, gateway_security_url)
          .to_return(status: 200, headers: { 'x-amzn-remapped-authorization' => 'Bearer gateway-token' })
        stub_request(:get, %r{#{Regexp.escape(host)}/v1/medicalrecords/})
          .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })
      end

      it 'posts to the API gateway security endpoint' do
        client.get_allergies_by_date(patient_id: '123', start_date: '2024-01-01', end_date: '2025-01-01')

        expect(WebMock).to have_requested(:post, gateway_security_url)
      end

      it 'sends x-api-key header on the login request' do
        client.get_allergies_by_date(patient_id: '123', start_date: '2024-01-01', end_date: '2025-01-01')

        expect(WebMock).to have_requested(:post, gateway_security_url)
          .with(headers: { 'x-api-key' => Settings.mhv.uhd.x_api_key })
      end

      it 'reads the x-amzn-remapped-authorization header from the login response' do
        client.get_allergies_by_date(patient_id: '123', start_date: '2024-01-01', end_date: '2025-01-01')

        expect(WebMock).to have_requested(:get, %r{#{Regexp.escape(host)}/v1/medicalrecords/allergies})
          .with(headers: { 'Authorization' => 'Bearer gateway-token' })
      end
    end

    context 'when mhv_uhd_api_gateway_security_endpoint is enabled but reached directly (NLB, no gateway remap)' do
      before do
        allow(Flipper).to receive(:enabled?).with(:mhv_uhd_api_gateway_security_endpoint).and_return(true)
        stub_request(:post, gateway_security_url)
          .to_return(status: 200, headers: { 'authorization' => 'Bearer nlb-token' })
        stub_request(:get, %r{#{Regexp.escape(host)}/v1/medicalrecords/})
          .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })
      end

      it 'falls back to the standard authorization header from the login response' do
        client.get_allergies_by_date(patient_id: '123', start_date: '2024-01-01', end_date: '2025-01-01')

        expect(WebMock).to have_requested(:get, %r{#{Regexp.escape(host)}/v1/medicalrecords/allergies})
          .with(headers: { 'Authorization' => 'Bearer nlb-token' })
      end
    end
  end

  # WebMock is used instead of VCR cassettes here because these tests verify URL-encoding
  # of path segments (slashes, spaces, `#`). VCR matches on the final URI so it cannot
  # assert that the client correctly encodes special characters before the request is sent.
  describe '#get_note_by_source' do
    let(:host) { Settings.mhv.uhd.host }
    let(:security_host) { Settings.mhv.uhd.security_host }
    let(:patient_id) { '12345V67890' }
    let(:source) { UnifiedHealthData::SourceConstants::ORACLE_HEALTH }
    let(:record_id) { '20875576613' }
    let(:start_date) { '2024-01-01' }
    let(:end_date) { '2025-06-01' }
    let(:expected_query) { { 'patientId' => patient_id, 'startDate' => start_date, 'endDate' => end_date } }

    before do
      allow(Flipper).to receive(:enabled?).with(:mhv_uhd_api_gateway_security_endpoint).and_return(false)
      stub_request(:post, "#{security_host}/mhvapi/security/v1/login")
        .to_return(status: 200, headers: { 'authorization' => 'Bearer test-token' })
      stub_request(:get, %r{#{Regexp.escape(host)}/v1/medicalrecords/notes})
        .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })
    end

    it 'constructs the correct URL with oracle-health source' do
      client.get_note_by_source(patient_id:, source:, record_id:, start_date:, end_date:)

      expect(WebMock).to have_requested(:get,
                                        "#{host}/v1/medicalrecords/notes/oracle-health/20875576613")
        .with(query: expected_query)
    end

    it 'constructs the correct URL with vista source' do
      vista_source = UnifiedHealthData::SourceConstants::VISTA

      client.get_note_by_source(patient_id:, source: vista_source, record_id:, start_date:, end_date:)

      expect(WebMock).to have_requested(:get,
                                        "#{host}/v1/medicalrecords/notes/vista/20875576613")
        .with(query: expected_query)
    end

    it 'URL-encodes slashes and hashes in record_id' do
      special_record_id = 'F253/7227761#1834074'

      client.get_note_by_source(patient_id:, source:, record_id: special_record_id, start_date:, end_date:)

      expect(WebMock).to have_requested(:get,
                                        "#{host}/v1/medicalrecords/notes/oracle-health/F253%2F7227761%231834074")
        .with(query: expected_query)
    end

    it 'URL-encodes spaces in record_id' do
      spaced_record_id = 'note 123'

      client.get_note_by_source(patient_id:, source:, record_id: spaced_record_id, start_date:, end_date:)

      expect(WebMock).to have_requested(:get,
                                        "#{host}/v1/medicalrecords/notes/oracle-health/note%20123")
        .with(query: expected_query)
    end

    it 'URL-encodes special characters in source' do
      weird_source = 'oracle/health'

      client.get_note_by_source(patient_id:, source: weird_source, record_id:, start_date:, end_date:)

      expect(WebMock).to have_requested(:get,
                                        "#{host}/v1/medicalrecords/notes/oracle%2Fhealth/20875576613")
        .with(query: expected_query)
    end
  end

  describe '#request_headers' do
    let(:host) { Settings.mhv.uhd.host }
    let(:security_host) { Settings.mhv.uhd.security_host }

    before do
      allow(Flipper).to receive(:enabled?).with(:mhv_uhd_api_gateway_security_endpoint).and_return(false)
      stub_request(:post, "#{security_host}/mhvapi/security/v1/login")
        .to_return(status: 200, headers: { 'authorization' => 'Bearer test-token' })
      stub_request(:get, %r{#{Regexp.escape(host)}/v1/medicalrecords/})
        .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })
    end

    context 'when RequestStore has a request_id' do
      before do
        RequestStore.store['request_id'] = 'rails-request-abc-123'
      end

      after do
        RequestStore.store['request_id'] = nil
      end

      it 'sends the RequestStore request_id as X-Request-Id' do
        client.get_allergies_by_date(patient_id: '123', start_date: '2024-01-01', end_date: '2025-01-01')

        expect(WebMock).to have_requested(:get, %r{#{Regexp.escape(host)}/v1/medicalrecords/allergies})
          .with(headers: { 'X-Request-Id' => 'rails-request-abc-123' })
      end

      it 'does not log a fallback message' do
        allow(Rails.logger).to receive(:info)

        client.get_allergies_by_date(patient_id: '123', start_date: '2024-01-01', end_date: '2025-01-01')

        expect(Rails.logger).not_to have_received(:info)
          .with('UHD Client: Generated fallback X-Request-Id for non-HTTP context', anything)
      end
    end

    context 'when RequestStore has no request_id (e.g. Sidekiq job)' do
      before do
        RequestStore.store['request_id'] = nil
        allow(SecureRandom).to receive(:uuid).and_return('fallback-uuid-456')
        allow(Rails.logger).to receive(:info)
      end

      it 'generates a fallback UUID and sends it as X-Request-Id' do
        client.get_allergies_by_date(patient_id: '123', start_date: '2024-01-01', end_date: '2025-01-01')

        expect(WebMock).to have_requested(:get, %r{#{Regexp.escape(host)}/v1/medicalrecords/allergies})
          .with(headers: { 'X-Request-Id' => 'fallback-uuid-456' })
      end

      it 'logs the fallback request_id' do
        client.get_allergies_by_date(patient_id: '123', start_date: '2024-01-01', end_date: '2025-01-01')

        expect(Rails.logger).to have_received(:info)
          .with('UHD Client: Generated fallback X-Request-Id for non-HTTP context', request_id: 'fallback-uuid-456')
      end
    end

    it 'includes Content-Type when include_content_type is true' do
      stub_request(:post, %r{#{Regexp.escape(host)}/v1/medicalrecords/})
        .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })

      client.refill_prescription_orders({ orders: [] })

      expect(WebMock).to have_requested(:post, %r{#{Regexp.escape(host)}/v1/medicalrecords/medications/rx/refill})
        .with(headers: { 'Content-Type' => 'application/json' })
    end

    context 'when no_cache is true' do
      it 'includes Cache-Control: no-cache header' do
        client.get_allergies_by_date(patient_id: '123', start_date: '2024-01-01', end_date: '2025-01-01',
                                     no_cache: true)

        expect(WebMock).to have_requested(:get, %r{#{Regexp.escape(host)}/v1/medicalrecords/allergies})
          .with(headers: { 'Cache-Control' => 'no-cache' })
      end
    end

    context 'when no_cache is false (default)' do
      it 'does not include Cache-Control header' do
        client.get_allergies_by_date(patient_id: '123', start_date: '2024-01-01', end_date: '2025-01-01')

        expect(WebMock).to have_requested(:get, %r{#{Regexp.escape(host)}/v1/medicalrecords/allergies})
          .with { |req| !req.headers.key?('Cache-Control') }
      end
    end

    context 'x-mhv-client-application header' do
      after do
        RequestStore.store['additional_request_attributes'] = nil
      end

      it 'sends VAHB when source is va-health-benefits-app' do
        RequestStore.store['additional_request_attributes'] = { 'source' => 'va-health-benefits-app' }

        client.get_allergies_by_date(patient_id: '123', start_date: '2024-01-01', end_date: '2025-01-01')

        expect(WebMock).to have_requested(:get, %r{#{Regexp.escape(host)}/v1/medicalrecords/allergies})
          .with(headers: { 'x-mhv-client-application' => 'VAHB' })
      end

      it 'sends VAGOV when source is a web app name' do
        RequestStore.store['additional_request_attributes'] = { 'source' => 'medications' }

        client.get_allergies_by_date(patient_id: '123', start_date: '2024-01-01', end_date: '2025-01-01')

        expect(WebMock).to have_requested(:get, %r{#{Regexp.escape(host)}/v1/medicalrecords/allergies})
          .with(headers: { 'x-mhv-client-application' => 'VAGOV' })
      end

      it 'defaults to VAGOV when source is not set' do
        RequestStore.store['additional_request_attributes'] = nil

        client.get_allergies_by_date(patient_id: '123', start_date: '2024-01-01', end_date: '2025-01-01')

        expect(WebMock).to have_requested(:get, %r{#{Regexp.escape(host)}/v1/medicalrecords/allergies})
          .with(headers: { 'x-mhv-client-application' => 'VAGOV' })
      end

      it 'sends VAHB in a Sidekiq-like context when source is propagated from a mobile request' do
        # SidekiqStatsInstrumentation::ServerMiddleware can propagate source into RequestStore;
        # if the originating request was from the mobile app, VAHB attribution is intentional.
        RequestStore.store['additional_request_attributes'] = { 'source' => 'va-health-benefits-app' }
        RequestStore.store['request_id'] = nil

        allow(SecureRandom).to receive(:uuid).and_return('sidekiq-fallback-uuid')
        allow(Rails.logger).to receive(:info)

        client.get_allergies_by_date(patient_id: '123', start_date: '2024-01-01', end_date: '2025-01-01')

        expect(WebMock).to have_requested(:get, %r{#{Regexp.escape(host)}/v1/medicalrecords/allergies})
          .with(headers: { 'x-mhv-client-application' => 'VAHB', 'X-Request-Id' => 'sidekiq-fallback-uuid' })
      end
    end
  end

  describe '#extract_resource_type' do
    it 'extracts allergies from path' do
      path = '/uhd/v1/allergies?patientId=123'
      expect(client.send(:extract_resource_type, path)).to eq('allergies')
    end

    it 'extracts labs from path' do
      path = '/uhd/v1/labs?patientId=123'
      expect(client.send(:extract_resource_type, path)).to eq('labs')
    end

    it 'extracts conditions from path' do
      path = '/uhd/v1/conditions?patientId=123'
      expect(client.send(:extract_resource_type, path)).to eq('conditions')
    end

    it 'extracts notes from path' do
      path = '/uhd/v1/notes?patientId=123'
      expect(client.send(:extract_resource_type, path)).to eq('notes')
    end

    it 'extracts vitals from path' do
      path = '/uhd/v1/vitals?patientId=123'
      expect(client.send(:extract_resource_type, path)).to eq('vitals')
    end

    it 'extracts immunizations from path' do
      path = '/uhd/v1/immunizations?patientId=123'
      expect(client.send(:extract_resource_type, path)).to eq('immunizations')
    end

    it 'extracts prescriptions from path' do
      path = '/uhd/v1/prescriptions?patientId=123'
      expect(client.send(:extract_resource_type, path)).to eq('prescriptions')
    end

    it 'extracts avs from path' do
      path = '/uhd/v1/avs?patientId=123&apptId=abc'
      expect(client.send(:extract_resource_type, path)).to eq('avs')
    end

    it 'extracts ccd from nested path' do
      path = '/uhd/v1/ccd/oracle-health?patientId=123'
      expect(client.send(:extract_resource_type, path)).to eq('ccd')
    end

    it 'returns unknown for unrecognized paths' do
      path = '/some/other/path'
      expect(client.send(:extract_resource_type, path)).to eq('unknown')
    end
  end
end
