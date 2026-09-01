# frozen_string_literal: true

require 'rails_helper'

describe Eps::ProviderService do
  user_icn = '123456789V123456'
  let(:service) { described_class.new(user) }
  let(:user) do
    double('User', account_uuid: '1234', uuid: 'user-uuid-123', icn: user_icn, va_treatment_facility_ids: ['123'])
  end

  before do
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:error)
    allow(Rails.logger).to receive(:debug)
    allow(Rails.logger).to receive(:public_send)
    allow(Rails.logger).to receive(:warn)
    allow(StatsD).to receive(:increment)
    # Bypass token authentication which is tested in another spec
    allow(Settings.vaos.eps).to receive(:mock).and_return(true)
    # Set up RequestStore for controller name logging
    RequestStore.store['controller_name'] = 'VAOS::V2::AppointmentsController'
    # Clear eps_trace_id to ensure test isolation
    RequestStore.store['eps_trace_id'] = nil
    # Mock PersonalInformationLog to avoid database interactions during tests
    allow(PersonalInformationLog).to receive(:create)
  end

  describe '#get_provider_service' do
    let(:provider_id) { 123 }
    let(:config) { instance_double(Eps::Configuration) }
    let(:headers) { { 'Authorization' => 'Bearer token123', 'X-Correlation-ID' => 'test-correlation-id' } }

    before do
      allow(config).to receive_messages(base_path: 'api/v1', mock_enabled?: false,
                                        request_types: %i[get put post delete],
                                        pagination_timeout_seconds: 45)
      allow(service).to receive_messages(config:)
      allow(service).to receive(:request_headers_with_correlation_id).and_return(headers)
    end

    context 'when the request is successful' do
      let(:response) do
        double('Response', status: 200, body: { id: provider_id, name: 'Provider 1' },
                           response_headers: { 'Content-Type' => 'application/json' })
      end

      before do
        allow_any_instance_of(VAOS::SessionService).to receive(:perform).and_return(response)
      end

      it 'returns an OpenStruct with the response body' do
        result = service.get_provider_service(provider_id:)

        expect(result).to eq(OpenStruct.new(response.body))
      end
    end

    context 'when the request fails' do
      let(:response) { double('Response', status: 500, body: 'Unknown service exception') }
      let(:exception) do
        Common::Exceptions::BackendServiceException.new(nil, {}, response.status, response.body)
      end

      before do
        allow_any_instance_of(VAOS::SessionService).to receive(:perform).and_raise(exception)
      end

      it 'raises an error' do
        expect do
          service.get_provider_service(provider_id:)
        end.to raise_error(Common::Exceptions::BackendServiceException, /VA900/)
      end
    end

    context 'when Eps::ServiceException is raised' do
      let(:eps_exception) do
        create_eps_exception(
          code: 'VAOS_401',
          status: 401,
          body: '{"name": "Unauthorized"}'
        )
      end

      before do
        allow_any_instance_of(VAOS::SessionService).to receive(:perform).and_raise(eps_exception)
        allow(Rails.logger).to receive(:error)
      end

      it 'logs EPS error with sanitized context and re-raises' do
        expect(Rails.logger).to receive(:error).with(
          'Community Care Appointments: EPS service error',
          hash_including(
            service: 'EPS',
            method: 'get_provider_service',
            error_class: 'Eps::ServiceException',
            timestamp: a_string_matching(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z/),
            code: 'VAOS_401',
            upstream_status: 401,
            upstream_body: '{\"name\": \"Unauthorized\"}'
          )
        )

        expect do
          service.get_provider_service(provider_id:)
        end.to raise_error(Eps::ServiceException)
      end
    end

    context 'when provider_id parameter is missing or blank' do
      it 'raises ArgumentError and logs StatsD metric and Rails warning when provider_id is nil' do
        expect(StatsD).to receive(:increment).with(
          'api.vaos.provider_service.no_params',
          tags: ['service:community_care_appointments']
        )
        expect(Rails.logger).to receive(:warn).with(
          'Community Care Appointments: Provider service called with no parameters',
          hash_including(
            method: 'get_provider_service',
            service: 'eps_provider_service',
            user_uuid: 'user-uuid-123'
          )
        )

        expect do
          service.get_provider_service(provider_id: nil)
        end.to raise_error(ArgumentError, 'provider_id is required and cannot be blank')
      end

      it 'raises ArgumentError and logs StatsD metric and Rails warning when provider_id is empty string' do
        expect(StatsD).to receive(:increment).with(
          'api.vaos.provider_service.no_params',
          tags: ['service:community_care_appointments']
        )
        expect(Rails.logger).to receive(:warn).with(
          'Community Care Appointments: Provider service called with no parameters',
          hash_including(
            method: 'get_provider_service',
            service: 'eps_provider_service',
            user_uuid: 'user-uuid-123'
          )
        )

        expect do
          service.get_provider_service(provider_id: '')
        end.to raise_error(ArgumentError, 'provider_id is required and cannot be blank')
      end

      it 'raises ArgumentError and logs StatsD metric and Rails warning when provider_id is blank' do
        expect(StatsD).to receive(:increment).with(
          'api.vaos.provider_service.no_params',
          tags: ['service:community_care_appointments']
        )
        expect(Rails.logger).to receive(:warn).with(
          'Community Care Appointments: Provider service called with no parameters',
          hash_including(
            method: 'get_provider_service',
            service: 'eps_provider_service',
            user_uuid: 'user-uuid-123'
          )
        )

        expect do
          service.get_provider_service(provider_id: '   ')
        end.to raise_error(ArgumentError, 'provider_id is required and cannot be blank')
      end
    end
  end

  describe '#get_networks' do
    let(:config) { instance_double(Eps::Configuration) }
    let(:headers) { { 'Authorization' => 'Bearer token123', 'X-Correlation-ID' => 'test-correlation-id' } }

    before do
      allow(config).to receive_messages(base_path: 'api/v1', mock_enabled?: false,
                                        request_types: %i[get put post delete])
      allow(service).to receive_messages(config:)
      allow(service).to receive(:request_headers_with_correlation_id).and_return(headers)
    end

    context 'when the request is successful' do
      let(:response) do
        double('Response', status: 200, body: { count: 1,
                                                networks: [
                                                  { id: 'network-5vuTac8v', name: 'Care Navigation' },
                                                  { id: 'network-2Awee9b5', name: 'Take Care Navigation' }
                                                ] },
                           response_headers: { 'Content-Type' => 'application/json' })
      end

      before do
        allow_any_instance_of(VAOS::SessionService).to receive(:perform).and_return(response)
      end

      it 'returns an OpenStruct with the response body' do
        result = service.get_networks

        expect(result).to eq(OpenStruct.new(response.body))
      end
    end

    context 'when the request fails' do
      let(:response) { double('Response', status: 500, body: 'Unknown service exception') }
      let(:exception) do
        Common::Exceptions::BackendServiceException.new(nil, {}, response.status, response.body)
      end

      before do
        allow_any_instance_of(VAOS::SessionService).to receive(:perform).and_raise(exception)
      end

      it 'raises an error' do
        expect { service.get_networks }.to raise_error(Common::Exceptions::BackendServiceException, /VA900/)
      end
    end

    context 'when Eps::ServiceException is raised' do
      let(:eps_exception) do
        create_eps_exception(
          code: 'VAOS_500',
          status: 500,
          body: '{"error": "Internal Service Exception"}'
        )
      end

      before do
        allow_any_instance_of(VAOS::SessionService).to receive(:perform).and_raise(eps_exception)
        allow(Rails.logger).to receive(:error)
      end

      it 'logs EPS error with sanitized context and re-raises' do
        expect(Rails.logger).to receive(:error).with(
          'Community Care Appointments: EPS service error',
          hash_including(
            service: 'EPS',
            method: 'get_networks',
            error_class: 'Eps::ServiceException',
            timestamp: a_string_matching(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z/),
            code: 'VAOS_500',
            upstream_status: 500,
            upstream_body: '{\"error\": \"Internal Service Exception\"}'
          )
        )

        expect do
          service.get_networks
        end.to raise_error(Eps::ServiceException)
      end
    end
  end

  describe '#get_provider_services_by_ids' do
    let(:provider_ids) { %w[provider1 provider2] }
    let(:config) { instance_double(Eps::Configuration) }
    let(:headers) { { 'Authorization' => 'Bearer token123', 'X-Correlation-ID' => 'test-correlation-id' } }

    before do
      allow(config).to receive_messages(base_path: 'api/v1', mock_enabled?: false,
                                        request_types: %i[get put post delete])
      allow(service).to receive_messages(config:)
      allow(service).to receive(:request_headers_with_correlation_id).and_return(headers)
    end

    context 'when the request is successful' do
      let(:response) do
        double('Response', status: 200, body: {
                 count: 2,
                 provider_services: [
                   { id: 'provider1', name: 'Provider 1' },
                   { id: 'provider2', name: 'Provider 2' }
                 ]
               }, response_headers: { 'Content-Type' => 'application/json' })
      end

      before do
        allow_any_instance_of(VAOS::SessionService).to receive(:perform).and_return(response)
      end

      it 'returns an OpenStruct with the response body' do
        result = service.get_provider_services_by_ids(provider_ids:)

        expect(result).to eq(OpenStruct.new(response.body))
      end

      it 'calls perform with multiple id parameters as required by backend' do
        expected_url = '/api/v1/provider-services?id=provider1&id=provider2'
        expect_any_instance_of(VAOS::SessionService).to receive(:perform).with(
          :get,
          expected_url,
          {},
          headers
        ).and_return(response)

        service.get_provider_services_by_ids(provider_ids:)
      end
    end

    # The id lookup is paginated by the same nextToken contract as the location search, so a
    # request for more ids than fit on one page has to follow the token or it drops providers.
    context 'when the id lookup spans multiple pages' do
      before do
        allow(config).to receive(:pagination_timeout_seconds).and_return(45)
        allow(service).to receive(:perform).and_return(
          double('Page1', status: 200,
                          body: { count: 1, provider_services: [{ id: 'provider1' }],
                                  next_token: 'token-page-2' },
                          response_headers: {}),
          double('Page2', status: 200,
                          body: { count: 1, provider_services: [{ id: 'provider2' }] },
                          response_headers: {})
        )
      end

      it 'aggregates providers across pages and reports the combined count' do
        result = service.get_provider_services_by_ids(provider_ids:)

        expect(result[:provider_services].pluck(:id)).to eq(%w[provider1 provider2])
        expect(result[:count]).to eq(2)
      end

      it 'drops the id query string on follow-up pages in favor of the token alone' do
        service.get_provider_services_by_ids(provider_ids:)

        expect(service).to have_received(:perform).with(
          :get, '/api/v1/provider-services?id=provider1&id=provider2', {}, headers
        ).ordered
        expect(service).to have_received(:perform).with(
          :get, '/api/v1/provider-services', { nextToken: 'token-page-2' }, headers
        ).ordered
      end
    end

    context 'when the request fails' do
      let(:response) { double('Response', status: 500, body: 'Unknown service exception') }
      let(:exception) do
        Common::Exceptions::BackendServiceException.new(nil, {}, response.status, response.body)
      end

      before do
        allow_any_instance_of(VAOS::SessionService).to receive(:perform).and_raise(exception)
      end

      it 'raises an error' do
        expect do
          service.get_provider_services_by_ids(provider_ids:)
        end.to raise_error(Common::Exceptions::BackendServiceException, /VA900/)
      end
    end

    context 'when Eps::ServiceException is raised' do
      let(:eps_exception) do
        create_eps_exception(
          code: 'VAOS_401',
          status: 401,
          body: '{"name": "Unauthorized"}'
        )
      end

      before do
        allow_any_instance_of(VAOS::SessionService).to receive(:perform).and_raise(eps_exception)
        allow(Rails.logger).to receive(:error)
      end

      it 'logs EPS error with sanitized context and re-raises' do
        expect(Rails.logger).to receive(:error).with(
          'Community Care Appointments: EPS service error',
          hash_including(
            service: 'EPS',
            method: 'get_provider_services_by_ids',
            error_class: 'Eps::ServiceException',
            timestamp: a_string_matching(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z/),
            code: 'VAOS_401',
            upstream_status: 401,
            upstream_body: '{\"name\": \"Unauthorized\"}'
          )
        )

        expect do
          service.get_provider_services_by_ids(provider_ids:)
        end.to raise_error(Eps::ServiceException)
      end
    end

    context 'when provider_ids parameter is missing or blank' do
      it 'returns empty provider_services and logs StatsD metric and Rails warning when provider_ids is nil' do
        expect(StatsD).to receive(:increment).with(
          'api.vaos.provider_service.no_params',
          tags: ['service:community_care_appointments']
        )
        expect(Rails.logger).to receive(:warn).with(
          'Community Care Appointments: Provider service called with no parameters',
          hash_including(
            method: 'get_provider_services_by_ids',
            service: 'eps_provider_service'
          )
        )

        result = service.get_provider_services_by_ids(provider_ids: nil)
        expect(result).to eq(OpenStruct.new(provider_services: []))
      end

      it 'returns empty provider_services and logs StatsD metric and Rails warning when provider_ids is empty array' do
        expect(StatsD).to receive(:increment).with(
          'api.vaos.provider_service.no_params',
          tags: ['service:community_care_appointments']
        )
        expect(Rails.logger).to receive(:warn).with(
          'Community Care Appointments: Provider service called with no parameters',
          hash_including(
            method: 'get_provider_services_by_ids',
            service: 'eps_provider_service'
          )
        )

        result = service.get_provider_services_by_ids(provider_ids: [])
        expect(result).to eq(OpenStruct.new(provider_services: []))
      end
    end
  end

  describe 'get_drive_times' do
    let(:config) { instance_double(Eps::Configuration) }
    let(:headers) { { 'Authorization' => 'Bearer token123', 'X-Correlation-ID' => 'test-correlation-id' } }
    let(:destinations) do
      {
        'provider-123' => {
          latitude: 40.7128,
          longitude: -74.0060
        }
      }
    end
    let(:origin) do
      {
        latitude: 40.7589,
        longitude: -73.9851
      }
    end

    before do
      allow(config).to receive_messages(base_path: 'api/v1', mock_enabled?: false,
                                        request_types: %i[get put post delete])
      allow(service).to receive_messages(config:)
      allow(service).to receive(:request_headers_with_correlation_id).and_return(headers)
    end

    context 'when the request is successful' do
      let(:response) do
        double('Response', status: 200, body: {
                                          'destinations' => {
                                            '00eff3f3-ecfb-41ff-9ebc-78ed811e17f9' => {
                                              'distanceInMiles' => '4',
                                              'driveTimeInSecondsWithTraffic' => '566',
                                              'driveTimeInSecondsWithoutTraffic' => '493',
                                              'latitude' => '-74.12870564772521',
                                              'longitude' => '-151.6240405624497'
                                            }
                                          },
                                          'origin' => {
                                            'latitude' => '4.627174468915552',
                                            'longitude' => '-88.72187894562788'
                                          }
                                        },
                           response_headers: { 'Content-Type' => 'application/json' })
      end

      before do
        allow_any_instance_of(VAOS::SessionService).to receive(:perform).and_return(response)
      end

      it 'returns the calculated drive times' do
        result = service.get_drive_times(destinations:, origin:)

        expect(result).to eq(OpenStruct.new(response.body))
      end
    end

    context 'when the request fails' do
      let(:response) { double('Response', status: 500, body: 'Unknown service exception') }
      let(:exception) do
        Common::Exceptions::BackendServiceException.new(nil, {}, response.status, response.body)
      end

      before do
        allow_any_instance_of(VAOS::SessionService).to receive(:perform).and_raise(exception)
      end

      it 'raises an error' do
        expect do
          service.get_drive_times(destinations:, origin:)
        end.to raise_error(Common::Exceptions::BackendServiceException, /VA900/)
      end
    end

    context 'when Eps::ServiceException is raised' do
      let(:eps_exception) do
        create_eps_exception(
          code: 'VAOS_400',
          status: 400,
          body: '{"name":"invalid_range","id":"aVFqt9NH",' \
                '"message":"body.latitude must be lesser or equal than 90 but got value 91",' \
                '"temporary":false,"timeout":false,"fault":false}'
        )
      end

      before do
        allow_any_instance_of(VAOS::SessionService).to receive(:perform).and_raise(eps_exception)
        allow(Rails.logger).to receive(:error)
      end

      it 'logs EPS error with sanitized context and re-raises' do
        expect(Rails.logger).to receive(:error).with(
          'Community Care Appointments: EPS service error',
          hash_including(
            service: 'EPS',
            method: 'get_drive_times',
            error_class: 'Eps::ServiceException',
            timestamp: a_string_matching(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z/),
            code: 'VAOS_400',
            upstream_status: 400,
            upstream_body: '{\"name\":\"invalid_range\",\"id\":\"aVFqt9NH\",' \
                           '\"message\":\"body.latitude must be lesser or equal than 90 but got value 91\",' \
                           '\"temporary\":false,\"timeout\":false,\"fault\":false}'
          )
        )

        expect do
          service.get_drive_times(destinations:, origin:)
        end.to raise_error(Eps::ServiceException)
      end
    end
  end

  describe '#get_provider_slots' do
    let(:provider_id) { '9mN718pH' }
    let(:required_params) do
      {
        appointmentTypeId: 'type123',
        startOnOrAfter: '2024-01-01T00:00:00Z',
        startBefore: '2024-01-02T00:00:00Z',
        appointmentId: '123'
      }
    end

    context 'when provider_id is invalid' do
      let(:config) { instance_double(Eps::Configuration) }
      let(:headers) { { 'Authorization' => 'Bearer token123', 'X-Correlation-ID' => 'test-correlation-id' } }

      before do
        allow(config).to receive_messages(base_path: 'api/v1', mock_enabled?: false,
                                          request_types: %i[get put post delete],
                                          pagination_timeout_seconds: 45)
        allow(service).to receive_messages(config:)
        allow(service).to receive(:request_headers_with_correlation_id).and_return(headers)
      end

      it 'raises ArgumentError when provider_id is nil' do
        expect do
          service.get_provider_slots(nil, required_params)
        end.to raise_error(ArgumentError, 'provider_id is required and cannot be blank')
      end

      it 'raises ArgumentError when provider_id is empty' do
        expect do
          service.get_provider_slots('', required_params)
        end.to raise_error(ArgumentError, 'provider_id is required and cannot be blank')
      end

      it 'raises ArgumentError when provider_id is blank' do
        expect do
          service.get_provider_slots('   ', required_params)
        end.to raise_error(ArgumentError, 'provider_id is required and cannot be blank')
      end
    end

    context 'when required parameters are missing' do
      let(:config) { instance_double(Eps::Configuration) }
      let(:headers) { { 'Authorization' => 'Bearer token123', 'X-Correlation-ID' => 'test-correlation-id' } }

      before do
        allow(config).to receive_messages(base_path: 'api/v1', mock_enabled?: false,
                                          request_types: %i[get put post delete],
                                          pagination_timeout_seconds: 45)
        allow(service).to receive_messages(config:)
        allow(service).to receive(:request_headers_with_correlation_id).and_return(headers)
      end

      it 'raises ArgumentError when appointmentTypeId is missing' do
        expect do
          service.get_provider_slots(provider_id, required_params.except(:appointmentTypeId))
        end.to raise_error(ArgumentError, /Missing required parameters: appointmentTypeId/)
      end

      it 'raises ArgumentError when startOnOrAfter is missing' do
        expect do
          service.get_provider_slots(provider_id, required_params.except(:startOnOrAfter))
        end.to raise_error(ArgumentError, /Missing required parameters: startOnOrAfter/)
      end

      it 'raises ArgumentError when startBefore is missing' do
        expect do
          service.get_provider_slots(provider_id, required_params.except(:startBefore))
        end.to raise_error(ArgumentError, /Missing required parameters: startBefore/)
      end

      it 'raises ArgumentError when appointmentId is missing' do
        expect do
          service.get_provider_slots(provider_id, required_params.except(:appointmentId))
        end.to raise_error(ArgumentError, /Missing required parameters: appointmentId/)
      end

      it 'raises ArgumentError when multiple required parameters are missing' do
        expect do
          service.get_provider_slots(provider_id, required_params.except(:startOnOrAfter, :startBefore))
        end.to raise_error(ArgumentError, /Missing required parameters: startOnOrAfter, startBefore/)
      end
    end

    context 'when single page response (no pagination)', :vcr do
      it 'returns an OpenStruct with all slots and correct count' do
        VCR.use_cassette('vaos/eps/get_provider_slots/200') do
          result = service.get_provider_slots('Aq7wgAux', {
                                                appointmentTypeId: 'ov',
                                                startOnOrAfter: '2025-01-01T00:00:00Z',
                                                startBefore: '2025-01-03T00:00:00Z',
                                                appointmentId: '123'
                                              })

          expect(result).to be_a(OpenStruct)
          expect(result.slots.length).to eq(2)
          expect(result.count).to eq(2)
          expect(result.slots.first[:id]).to include('5vuTac8v-practitioner')
        end
      end

      it 'removes nextToken from response' do
        VCR.use_cassette('vaos/eps/get_provider_slots/200') do
          result = service.get_provider_slots('Aq7wgAux', {
                                                appointmentTypeId: 'ov',
                                                startOnOrAfter: '2025-01-01T00:00:00Z',
                                                startBefore: '2025-01-03T00:00:00Z',
                                                appointmentId: '123'
                                              })

          expect(result.to_h).not_to have_key(:next_token)
          expect(result.to_h).not_to have_key(:nextToken)
        end
      end
    end

    context 'when empty response', :vcr do
      it 'returns empty slots array with zero count' do
        VCR.use_cassette('vaos/eps/get_provider_slots/200_no_slots') do
          result = service.get_provider_slots('9mN718pH', {
                                                appointmentTypeId: 'ov',
                                                startOnOrAfter: '2025-01-01T00:00:00Z',
                                                startBefore: '2025-01-03T00:00:00Z',
                                                appointmentId: '123'
                                              })

          expect(result.slots).to eq([])
          expect(result.count).to eq(0)
        end
      end
    end

    context 'when pagination timeout occurs' do
      it 'raises BackendServiceException when timeout exceeded using VCR', :vcr do
        # Use Timecop to simulate timeout during pagination
        Timecop.freeze(Time.zone.parse('2024-01-01 12:00:00')) do
          expect(Rails.logger).to receive(:error)

          # Simulate time advancing during the API call
          allow_any_instance_of(VAOS::SessionService).to receive(:perform) do
            Timecop.travel(46.seconds) # Advance time to trigger timeout
            # Return a response that would normally continue pagination
            double('Response', body: { slots: [{ id: 'test' }], next_token: 'token123' })
          end

          VCR.use_cassette('vaos/eps/get_provider_slots/timeout_simulation') do
            expect do
              service.get_provider_slots('TIMEOUT_TEST', {
                                           appointmentTypeId: 'ov',
                                           startOnOrAfter: '2025-01-01T00:00:00Z',
                                           startBefore: '2025-01-03T00:00:00Z',
                                           appointmentId: '123'
                                         })
            end.to raise_error(Common::Exceptions::BackendServiceException) { |error|
              expect(error.key).to eq('PROVIDER_SLOTS_TIMEOUT')
            }
          end
        end
      end
    end

    context 'when API request fails' do
      let(:config) { instance_double(Eps::Configuration) }
      let(:headers) { { 'Authorization' => 'Bearer token123', 'X-Correlation-ID' => 'test-correlation-id' } }
      let(:exception) do
        Common::Exceptions::BackendServiceException.new(nil, {}, 500, 'Unknown service exception')
      end

      before do
        allow(config).to receive_messages(base_path: 'api/v1', mock_enabled?: false,
                                          request_types: %i[get put post delete],
                                          pagination_timeout_seconds: 45)
        allow(service).to receive_messages(config:)
        allow(service).to receive(:request_headers_with_correlation_id).and_return(headers)
        allow_any_instance_of(VAOS::SessionService).to receive(:perform).and_raise(exception)
      end

      it 'raises the original exception' do
        expect do
          service.get_provider_slots(provider_id, required_params)
        end.to raise_error(Common::Exceptions::BackendServiceException, /VA900/)
      end
    end

    context 'when multiple page response (with pagination)', :vcr do
      it 'handles pagination from VCR cassette' do
        VCR.use_cassette('vaos/eps/get_provider_slots/200_with_pagination') do
          result = service.get_provider_slots('TEST123', {
                                                appointmentTypeId: 'ov',
                                                startOnOrAfter: '2025-01-01T00:00:00Z',
                                                startBefore: '2025-01-03T00:00:00Z',
                                                appointmentId: '123'
                                              })

          expect(result).to be_a(OpenStruct)
          expect(result.slots.length).to eq(3)
          expect(result.count).to eq(3)
          expect(result.slots.map { |slot| slot[:id] }).to include(
            'page1-slot1|2025-01-02T09:00:00Z',
            'page1-slot2|2025-01-02T10:00:00Z',
            'page3-slot1|2025-01-02T14:00:00Z'
          )
          expect(result.to_h).not_to have_key(:next_token)
        end
      end
    end
  end

  describe '#search_provider_services' do
    let(:npi) { '7894563210' }
    let(:specialty) { 'Cardiology' }

    context 'when required parameters are missing or blank' do
      it 'raises ArgumentError and logs personal information when npi is nil' do
        expect(PersonalInformationLog).to receive(:create).with(
          error_class: 'eps_provider_npi_missing',
          data: hash_including(
            search_params: hash_including(specialty:),
            failure_reason: 'NPI parameter is blank'
          )
        )

        expect do
          service.search_provider_services(npi: nil, specialty:)
        end.to raise_error(ArgumentError, 'Provider NPI is required and cannot be blank')
      end

      it 'raises ArgumentError when npi is empty string' do
        expect do
          service.search_provider_services(npi: '', specialty:)
        end.to raise_error(ArgumentError, 'Provider NPI is required and cannot be blank')
      end

      it 'raises ArgumentError when npi is blank' do
        expect do
          service.search_provider_services(npi: '   ', specialty:)
        end.to raise_error(ArgumentError, 'Provider NPI is required and cannot be blank')
      end

      it 'raises ArgumentError and logs personal information when specialty is nil' do
        expect(PersonalInformationLog).to receive(:create).with(
          error_class: 'eps_provider_specialty_missing',
          data: hash_including(
            npi:,
            failure_reason: 'Specialty parameter is blank'
          )
        )

        expect do
          service.search_provider_services(npi:, specialty: nil)
        end.to raise_error(ArgumentError, 'Provider specialty is required and cannot be blank')
      end

      it 'raises ArgumentError when specialty is empty string' do
        expect do
          service.search_provider_services(npi:, specialty: '')
        end.to raise_error(ArgumentError, 'Provider specialty is required and cannot be blank')
      end

      it 'raises ArgumentError when specialty is blank' do
        expect do
          service.search_provider_services(npi:, specialty: '   ')
        end.to raise_error(ArgumentError, 'Provider specialty is required and cannot be blank')
      end
    end

    context 'when the request is successful' do
      context 'when provider specialty does not match' do
        let(:response_body) do
          {
            count: 1,
            provider_services: [
              self_schedulable_provider(specialties: [{ name: 'Dermatology' }])
            ]
          }
        end

        let(:response) do
          double('Response', status: 200, body: response_body,
                             response_headers: { 'Content-Type' => 'application/json' })
        end

        before do
          allow_any_instance_of(VAOS::SessionService).to receive(:perform).and_return(response)
        end

        it 'returns nil and logs personal information' do
          expect(PersonalInformationLog).to receive(:create).with(
            error_class: 'eps_provider_specialty_mismatch',
            data: hash_including(
              npi:,
              search_params: hash_including(specialty:),
              failure_reason: "No providers match specialty '#{specialty}'"
            )
          )

          result = service.search_provider_services(npi:, specialty:)
          expect(result).to be_nil
        end
      end

      context 'when the response contains no providers' do
        let(:response_body) do
          {
            count: 0,
            provider_services: []
          }
        end

        let(:response) do
          double('Response', status: 200, body: response_body,
                             response_headers: { 'Content-Type' => 'application/json' })
        end

        before do
          allow_any_instance_of(VAOS::SessionService).to receive(:perform).and_return(response)
        end

        it 'returns nil and logs personal information' do
          expect(PersonalInformationLog).to receive(:create).with(
            error_class: 'eps_provider_no_providers_found',
            data: hash_including(
              npi:,
              failure_reason: 'No providers returned from EPS API for NPI'
            )
          )

          result = service.search_provider_services(npi:, specialty:)
          expect(result).to be_nil
        end
      end

      context 'when provider has blank specialty' do
        let(:response_body) do
          {
            count: 1,
            provider_services: [
              self_schedulable_provider(specialties: [])
            ]
          }
        end

        let(:response) do
          double('Response', status: 200, body: response_body,
                             response_headers: { 'Content-Type' => 'application/json' })
        end

        before do
          allow_any_instance_of(VAOS::SessionService).to receive(:perform).and_return(response)
        end

        it 'returns nil' do
          result = service.search_provider_services(npi:, specialty:)
          expect(result).to be_nil
        end
      end

      context 'when providers are returned but none are self-schedulable' do
        let(:response_body) do
          {
            count: 2,
            provider_services: [
              {
                id: 'provider1',
                specialties: [{ name: 'Cardiology' }],
                features: {
                  is_digital: false,
                  direct_booking: {
                    is_enabled: true
                  }
                },
                location: {
                  address: '1105 Palmetto Ave, Melbourne, FL, 32901'
                }
              },
              {
                id: 'provider2',
                specialties: [{ name: 'Cardiology' }],
                features: {
                  is_digital: true,
                  direct_booking: {
                    is_enabled: false
                  }
                },
                location: {
                  address: '1105 Palmetto Ave, Melbourne, FL, 32901'
                }
              }
            ]
          }
        end

        let(:response) do
          double('Response', status: 200, body: response_body,
                             response_headers: { 'Content-Type' => 'application/json' })
        end

        before do
          allow_any_instance_of(VAOS::SessionService).to receive(:perform).and_return(response)
          allow(Rails.logger).to receive(:error)
        end

        it 'returns nil, logs error, increments metric, and logs personal information' do
          expect(StatsD).to receive(:increment).with(
            'api.vaos.provider_service.no_self_schedulable',
            tags: ['service:community_care_appointments']
          )
          expect(PersonalInformationLog).to receive(:create).with(
            error_class: 'eps_provider_no_self_schedulable',
            data: hash_including(
              npi:,
              failure_reason: match(/No self-schedulable providers found/)
            )
          )

          result = service.search_provider_services(npi:, specialty:)
          expect(result).to be_nil
          expected_controller_name = 'VAOS::V2::AppointmentsController'
          expected_station_number = user.va_treatment_facility_ids&.first
          expect(Rails.logger).to have_received(:error).with(
            'Community Care Appointments: No self-schedulable providers found for NPI',
            {
              controller: expected_controller_name,
              station_number: expected_station_number,
              eps_trace_id: nil,
              user_uuid: 'user-uuid-123'
            }
          )
        end
      end

      context 'when provider meets all self-schedulable criteria' do
        let(:response_body) do
          {
            count: 1,
            provider_services: [
              self_schedulable_provider
            ]
          }
        end

        let(:response) do
          double('Response', status: 200, body: response_body,
                             response_headers: { 'Content-Type' => 'application/json' })
        end

        before do
          allow_any_instance_of(VAOS::SessionService).to receive(:perform).and_return(response)
        end

        it 'returns the provider' do
          result = service.search_provider_services(npi:, specialty:)
          expect(result).to be_a(OpenStruct)
          expect(result.id).to eq('provider123')
        end
      end

      context 'when provider fails isDigital criteria' do
        let(:response_body) do
          {
            count: 1,
            provider_services: [
              self_schedulable_provider(
                features: {
                  is_digital: false,
                  direct_booking: {
                    is_enabled: true
                  }
                }
              )
            ]
          }
        end

        let(:response) do
          double('Response', status: 200, body: response_body,
                             response_headers: { 'Content-Type' => 'application/json' })
        end

        before do
          allow_any_instance_of(VAOS::SessionService).to receive(:perform).and_return(response)
          allow(Rails.logger).to receive(:error)
        end

        it 'returns nil, logs error, and increments metric' do
          expect(StatsD).to receive(:increment).with(
            'api.vaos.provider_service.no_self_schedulable',
            tags: ['service:community_care_appointments']
          )
          result = service.search_provider_services(npi:, specialty:)
          expect(result).to be_nil
          expected_controller_name = 'VAOS::V2::AppointmentsController'
          expected_station_number = user.va_treatment_facility_ids&.first
          expect(Rails.logger).to have_received(:error).with(
            'Community Care Appointments: No self-schedulable providers found for NPI',
            {
              controller: expected_controller_name,
              station_number: expected_station_number,
              eps_trace_id: nil,
              user_uuid: 'user-uuid-123'
            }
          )
        end
      end

      context 'when provider fails directBooking.isEnabled criteria' do
        let(:response_body) do
          {
            count: 1,
            provider_services: [
              self_schedulable_provider(
                features: {
                  is_digital: true,
                  direct_booking: {
                    is_enabled: false
                  }
                }
              )
            ]
          }
        end

        let(:response) do
          double('Response', status: 200, body: response_body,
                             response_headers: { 'Content-Type' => 'application/json' })
        end

        before do
          allow_any_instance_of(VAOS::SessionService).to receive(:perform).and_return(response)
          allow(Rails.logger).to receive(:error)
        end

        it 'returns nil, logs error, and increments metric' do
          expect(StatsD).to receive(:increment).with(
            'api.vaos.provider_service.no_self_schedulable',
            tags: ['service:community_care_appointments']
          )
          result = service.search_provider_services(npi:, specialty:)
          expect(result).to be_nil
          expected_controller_name = 'VAOS::V2::AppointmentsController'
          expected_station_number = user.va_treatment_facility_ids&.first
          expect(Rails.logger).to have_received(:error).with(
            'Community Care Appointments: No self-schedulable providers found for NPI',
            {
              controller: expected_controller_name,
              station_number: expected_station_number,
              eps_trace_id: nil,
              user_uuid: 'user-uuid-123'
            }
          )
        end
      end

      context 'when multiple self-schedulable providers exist' do
        let(:response_body) do
          {
            count: 2,
            provider_services: [
              self_schedulable_provider(
                id: 'provider1',
                location: {
                  address: '1601 NEEDMORE RD ; STE 1 & 2, DAYTON, OH 45414-3848'
                }
              ),
              self_schedulable_provider(
                id: 'provider2',
                location: {
                  address: '1601 NEEDMORE RD ; STE 1 & 2, DAYTON, OH 45414-3848'
                }
              )
            ]
          }
        end

        let(:response) do
          double('Response', status: 200, body: response_body,
                             response_headers: { 'Content-Type' => 'application/json' })
        end

        before do
          allow_any_instance_of(VAOS::SessionService).to receive(:perform).and_return(response)
        end

        it 'returns the first matching provider' do
          result = service.search_provider_services(npi:, specialty: 'Cardiology')
          expect(result).to be_a(OpenStruct)
          expect(result.id).to eq('provider1')
        end
      end

      context 'when specialty matching is case-insensitive' do
        let(:response_body) do
          {
            count: 1,
            provider_services: [
              self_schedulable_provider(
                specialties: [{ name: 'CARDIOLOGY' }],
                location: {
                  address: '1601 NEEDMORE RD ; STE 1 & 2, DAYTON, OH 45414-3848'
                }
              )
            ]
          }
        end

        let(:response) do
          double('Response', status: 200, body: response_body,
                             response_headers: { 'Content-Type' => 'application/json' })
        end

        before do
          allow_any_instance_of(VAOS::SessionService).to receive(:perform).and_return(response)
        end

        it 'matches specialty regardless of case' do
          result = service.search_provider_services(npi:, specialty: 'cardiology')
          expect(result).to be_a(OpenStruct)
          expect(result.id).to eq('provider123')
        end
      end
    end

    context 'when the request fails' do
      let(:response) { double('Response', status: 500, body: 'Unknown service exception') }
      let(:exception) do
        Common::Exceptions::BackendServiceException.new(nil, {}, response.status, response.body)
      end

      before do
        allow_any_instance_of(VAOS::SessionService).to receive(:perform).and_raise(exception)
      end

      it 'raises an error' do
        expect { service.search_provider_services(npi:, specialty:) }
          .to raise_error(Common::Exceptions::BackendServiceException, /VA900/)
      end
    end
  end

  describe '#search_by_location' do
    let(:config) { instance_double(Eps::Configuration) }
    let(:headers) { { 'Authorization' => 'Bearer token123', 'X-Correlation-ID' => 'test-correlation-id' } }
    let(:response_body) do
      {
        provider_services: [
          {
            id: 'provider-self-urology',
            specialties: [{ name: 'Urology' }],
            features: {
              is_digital: true,
              direct_booking: { is_enabled: true }
            }
          },
          {
            id: 'provider-self-cardiology',
            specialties: [{ name: 'Cardiology' }],
            features: {
              is_digital: true,
              direct_booking: { is_enabled: true }
            }
          },
          {
            id: 'provider-not-self',
            specialties: [{ name: 'Urology' }],
            features: {
              is_digital: false,
              direct_booking: { is_enabled: true }
            }
          }
        ]
      }
    end
    let(:response) do
      double('Response', status: 200, body: response_body,
                         response_headers: { 'Content-Type' => 'application/json' })
    end

    before do
      allow(config).to receive_messages(base_path: 'api/v1', mock_enabled?: false,
                                        request_types: %i[get put post delete])
      allow(service).to receive_messages(config:)
      allow(service).to receive(:request_headers_with_correlation_id).and_return(headers)
      allow_any_instance_of(VAOS::SessionService).to receive(:perform).and_return(response)
    end

    # Wraps the search criteria in the value object the service now takes, so each example
    # can keep passing plain keyword args.
    def perform_search(**attrs)
      service.search_by_location(Eps::ProviderSearchQuery.new(**attrs))
    end

    it 'maps location params to EPS query params and filters by specialty' do
      expect_any_instance_of(VAOS::SessionService).to receive(:perform).with(
        :get,
        '/api/v1/provider-services',
        hash_including(
          nearLocation: '28.08,-80.6',
          maxMilesFromNear: 30,
          isSelfSchedulable: true
        ),
        headers
      ).and_return(response)

      result = perform_search(
        coordinates: { latitude: '28.08', longitude: '-80.6' }, radius: '30', specialty: 'Urology'
      )

      expect(result.map { |p| p[:id] }).to eq(['provider-self-urology'])
    end

    # Wellhive paginates ProviderServiceSearchResult via nextToken. Reading only the first
    # page silently dropped providers from any search whose results spilled past it.
    context 'when the result set spans multiple pages' do
      let(:first_page) do
        {
          provider_services: [
            { id: 'page1-provider', specialties: [{ name: 'Urology' }],
              features: { is_digital: true, direct_booking: { is_enabled: true } } }
          ],
          next_token: 'token-page-2'
        }
      end
      let(:second_page) do
        {
          provider_services: [
            { id: 'page2-provider', specialties: [{ name: 'Urology' }],
              features: { is_digital: true, direct_booking: { is_enabled: true } } }
          ]
        }
      end

      # Stubbed on the service instance rather than via allow_any_instance_of: RSpec's
      # any_instance support is not designed for several expectations on one method, and
      # this context needs to assert on the arguments of two successive perform calls.
      before do
        allow(config).to receive(:pagination_timeout_seconds).and_return(45)
        allow(service).to receive(:perform).and_return(
          double('Page1', status: 200, body: first_page, response_headers: {}),
          double('Page2', status: 200, body: second_page, response_headers: {})
        )
      end

      it 'follows nextToken and returns providers from every page' do
        result = perform_search(coordinates: { latitude: 28.08, longitude: -80.6 }, radius: 30)

        expect(result.map { |p| p[:id] }).to eq(%w[page1-provider page2-provider])
      end

      it 'sends the token alone on follow-up pages, since Wellhive ignores other params' do
        perform_search(coordinates: { latitude: '28.08', longitude: '-80.6' }, radius: 30)

        expect(service).to have_received(:perform).with(
          :get, '/api/v1/provider-services', hash_including(nearLocation: '28.08,-80.6'), headers
        ).ordered
        expect(service).to have_received(:perform).with(
          :get, '/api/v1/provider-services', { nextToken: 'token-page-2' }, headers
        ).ordered
      end

      it 'stops paginating once a page comes back without a token' do
        perform_search(coordinates: { latitude: 28.08, longitude: -80.6 }, radius: 30)

        expect(service).to have_received(:perform).twice
      end

      # A Wellhive bug that returned a cycling nextToken would otherwise spend the whole
      # 45s timeout window firing requests at a partner API.
      context 'when every page keeps returning a token' do
        before do
          allow(service).to receive(:perform).and_return(
            double('Page', status: 200, body: first_page, response_headers: {})
          )
        end

        it 'stops at the page cap instead of looping until the timeout' do
          perform_search(coordinates: { latitude: 28.08, longitude: -80.6 }, radius: 30)

          expect(service).to have_received(:perform).exactly(described_class::MAX_SEARCH_PAGES).times
        end

        it 'logs and counts the truncation rather than truncating silently' do
          perform_search(coordinates: { latitude: 28.08, longitude: -80.6 }, radius: 30)

          expect(Rails.logger).to have_received(:warn).with(
            /pagination hit page cap/, hash_including(max_pages: described_class::MAX_SEARCH_PAGES)
          )
          expect(StatsD).to have_received(:increment)
            .with(described_class::PROVIDER_SEARCH_PAGE_CAP_METRIC, anything)
        end
      end

      # The page cap bounds how many requests a search makes, not how long they take: 20
      # slow pages can still hold the request open well past the window slots pagination
      # has always been held to. Checked between pages only, so the first page is never
      # cut short and a single-page search never touches the timeout at all.
      context 'when pagination runs past the timeout window' do
        before do
          allow(service).to receive(:perform) do
            Timecop.travel(46.seconds)
            double('Page', status: 200, body: first_page, response_headers: {})
          end
        end

        it 'raises PROVIDER_SEARCH_TIMEOUT rather than fetching another page' do
          Timecop.freeze(Time.zone.parse('2024-01-01 12:00:00')) do
            expect do
              perform_search(coordinates: { latitude: 28.08, longitude: -80.6 }, radius: 30)
            end.to raise_error(Common::Exceptions::BackendServiceException) { |error|
              expect(error.key).to eq('PROVIDER_SEARCH_TIMEOUT')
            }

            expect(service).to have_received(:perform).once
          end
        end

        it 'logs the timeout with the configured window' do
          Timecop.freeze(Time.zone.parse('2024-01-01 12:00:00')) do
            expect do
              perform_search(coordinates: { latitude: 28.08, longitude: -80.6 }, radius: 30)
            end.to raise_error(Common::Exceptions::BackendServiceException)
          end

          expect(Rails.logger).to have_received(:error).with(
            /Provider services pagination timeout/, hash_including(timeout_seconds: 45)
          )
        end
      end
    end

    it 'returns self-schedulable providers when specialty is not provided' do
      result = perform_search(coordinates: { latitude: 28.08, longitude: -80.6 }, radius: 30)

      expect(result.map { |p| p[:id] }).to contain_exactly('provider-self-urology', 'provider-self-cardiology')
    end

    # Regression guard for the singular vs. plural query param Wellhive expects.
    # Wellhive silently ignores +specialtyIds+ (plural); the param it actually
    # filters on is +specialtyId+ (singular), repeated for multiple values.
    it 'sends the NUCC ids as the singular specialtyId query param (not specialtyIds)' do
      expect_any_instance_of(VAOS::SessionService).to receive(:perform).with(
        :get,
        '/api/v1/provider-services',
        hash_including(specialtyId: %w[207Q00000X 207R00000X 208D00000X]),
        headers
      ).and_return(response)

      perform_search(
        coordinates: { latitude: 28.08, longitude: -80.6 }, radius: 30,
        specialty_ids: %w[207Q00000X 207R00000X 208D00000X]
      )
    end

    it 'does not include specialtyId in the outbound query when no specialty_ids are given' do
      expect_any_instance_of(VAOS::SessionService).to receive(:perform) do |_inst, _verb, _path, query, _headers|
        expect(query).not_to have_key(:specialtyId)
        expect(query).not_to have_key(:specialtyIds)
        response
      end

      perform_search(coordinates: { latitude: 28.08, longitude: -80.6 }, radius: 30)
    end

    it 'compacts and de-duplicates specialty_ids before sending' do
      expect_any_instance_of(VAOS::SessionService).to receive(:perform).with(
        :get,
        '/api/v1/provider-services',
        hash_including(specialtyId: %w[207Q00000X 208D00000X]),
        headers
      ).and_return(response)

      perform_search(
        coordinates: { latitude: 28.08, longitude: -80.6 }, radius: 30,
        specialty_ids: ['207Q00000X', nil, '208D00000X', '207Q00000X']
      )
    end

    context 'when self_schedulable_only is false (post-MVP call-to-schedule)' do
      it 'omits the isSelfSchedulable query param' do
        expect_any_instance_of(VAOS::SessionService).to receive(:perform) do |_inst, _verb, _path, query, _headers|
          expect(query).not_to have_key(:isSelfSchedulable)
          response
        end

        perform_search(coordinates: { latitude: 28.08, longitude: -80.6 }, radius: 30,
                       self_schedulable_only: false)
      end

      it 'returns phone-only providers alongside self-schedulable ones' do
        result = perform_search(coordinates: { latitude: 28.08, longitude: -80.6 }, radius: 30,
                                self_schedulable_only: false)

        expect(result.map { |p| p[:id] })
          .to contain_exactly('provider-self-urology', 'provider-self-cardiology', 'provider-not-self')
      end

      it 'still applies client-side specialty filtering without dropping phone-only matches' do
        result = perform_search(
          coordinates: { latitude: 28.08, longitude: -80.6 }, radius: 30, specialty: 'Urology',
          self_schedulable_only: false
        )

        expect(result.map { |p| p[:id] }).to contain_exactly('provider-self-urology', 'provider-not-self')
      end
    end

    it 'raises ArgumentError when latitude is blank' do
      expect do
        perform_search(coordinates: { latitude: nil, longitude: -80.6 }, radius: 30)
      end.to raise_error(ArgumentError, 'latitude is required')
    end

    it 'raises ArgumentError when longitude is blank' do
      expect do
        perform_search(coordinates: { latitude: 28.08, longitude: nil }, radius: 30)
      end.to raise_error(ArgumentError, 'longitude is required')
    end

    context 'when Eps::ServiceException is raised' do
      let(:eps_exception) do
        create_eps_exception(
          code: 'VAOS_500',
          status: 500,
          body: '{"error":"Internal Service Exception"}'
        )
      end

      before do
        allow_any_instance_of(VAOS::SessionService).to receive(:perform).and_raise(eps_exception)
        allow(Rails.logger).to receive(:error)
      end

      it 'logs EPS error and re-raises' do
        expect(Rails.logger).to receive(:error).with(
          'Community Care Appointments: EPS service error',
          hash_including(
            service: 'EPS',
            method: 'search_by_location',
            error_class: 'Eps::ServiceException',
            code: 'VAOS_500',
            upstream_status: 500
          )
        )

        expect do
          perform_search(coordinates: { latitude: 28.08, longitude: -80.6 }, radius: 25)
        end.to raise_error(Eps::ServiceException)
      end
    end
  end

  describe '#fetch_provider_services' do
    let(:npi) { '1234567890' }
    let(:config) { instance_double(Eps::Configuration) }
    let(:headers) { { 'Authorization' => 'Bearer token123', 'X-Correlation-ID' => 'test-correlation-id' } }

    before do
      allow(config).to receive_messages(base_path: 'api/v1', mock_enabled?: false,
                                        request_types: %i[get put post delete])
      allow(service).to receive_messages(config:)
      allow(service).to receive(:request_headers_with_correlation_id).and_return(headers)
    end

    context 'when the request is successful' do
      let(:response) do
        double('Response', status: 200, body: {
                 count: 1,
                 provider_services: [
                   { id: 'provider1', npi:, name: 'Provider 1' }
                 ]
               }, response_headers: { 'Content-Type' => 'application/json' })
      end

      before do
        allow_any_instance_of(VAOS::SessionService).to receive(:perform).and_return(response)
      end

      it 'returns the response from perform' do
        result = service.send(:fetch_provider_services, npi)

        expect(result).to eq(response)
      end

      it 'calls perform with correct parameters including isSelfSchedulable' do
        expect_any_instance_of(VAOS::SessionService).to receive(:perform).with(
          :get,
          '/api/v1/provider-services',
          { npi:, isSelfSchedulable: true },
          headers
        ).and_return(response)

        service.send(:fetch_provider_services, npi)
      end
    end

    context 'when the request fails' do
      let(:response) { double('Response', status: 500, body: 'Unknown service exception') }
      let(:exception) do
        Common::Exceptions::BackendServiceException.new(nil, {}, response.status, response.body)
      end

      before do
        allow_any_instance_of(VAOS::SessionService).to receive(:perform).and_raise(exception)
      end

      it 'raises an error' do
        expect do
          service.send(:fetch_provider_services, npi)
        end.to raise_error(Common::Exceptions::BackendServiceException, /VA900/)
      end
    end

    context 'when npi parameter is missing or blank' do
      it 'raises ArgumentError and logs StatsD metric and Rails warning when npi is nil' do
        expect(StatsD).to receive(:increment).with(
          'api.vaos.provider_service.no_params',
          tags: ['service:community_care_appointments']
        )
        expect(Rails.logger).to receive(:warn).with(
          'Community Care Appointments: Provider service called with no parameters',
          hash_including(
            method: 'fetch_provider_services',
            service: 'eps_provider_service'
          )
        )

        expect do
          service.send(:fetch_provider_services, nil)
        end.to raise_error(ArgumentError, 'npi is required and cannot be blank')
      end

      it 'raises ArgumentError and logs StatsD metric and Rails warning when npi is empty string' do
        expect(StatsD).to receive(:increment).with(
          'api.vaos.provider_service.no_params',
          tags: ['service:community_care_appointments']
        )
        expect(Rails.logger).to receive(:warn).with(
          'Community Care Appointments: Provider service called with no parameters',
          hash_including(
            method: 'fetch_provider_services',
            service: 'eps_provider_service'
          )
        )

        expect do
          service.send(:fetch_provider_services, '')
        end.to raise_error(ArgumentError, 'npi is required and cannot be blank')
      end

      it 'raises ArgumentError and logs StatsD metric and Rails warning when npi is blank' do
        expect(StatsD).to receive(:increment).with(
          'api.vaos.provider_service.no_params',
          tags: ['service:community_care_appointments']
        )
        expect(Rails.logger).to receive(:warn).with(
          'Community Care Appointments: Provider service called with no parameters',
          hash_including(
            method: 'fetch_provider_services',
            service: 'eps_provider_service'
          )
        )

        expect do
          service.send(:fetch_provider_services, '   ')
        end.to raise_error(ArgumentError, 'npi is required and cannot be blank')
      end
    end
  end

  # Helper method to create a self-schedulable provider
  # Note: appointment_types field is included for API response completeness but
  # is not used for self-schedulable filtering (handled by EPS API via isSelfSchedulable param).
  # Self-schedulable filtering now only checks is_digital and direct_booking.is_enabled.
  def self_schedulable_provider(overrides = {})
    {
      id: 'provider123',
      specialties: [{ name: 'Cardiology' }],
      appointment_types: [
        {
          name: 'Office Visit',
          is_self_schedulable: true
        }
      ],
      features: {
        is_digital: true,
        direct_booking: {
          is_enabled: true
        }
      },
      location: {
        address: '1105 Palmetto Ave, Melbourne, FL, 32901'
      }
    }.merge(overrides)
  end

  # Helper method to create EPS exceptions with properly formatted messages
  def create_eps_exception(code:, status:, body:)
    exception = Eps::ServiceException.new(
      code,
      { code:, detail: 'Test error' },
      status,
      body
    )
    # Mock the message to include the parseable format for parse_eps_backend_fields
    allow(exception).to receive(:message).and_return(
      "BackendServiceException: {code: \"#{code}\", " \
      "source: {vamf_status: #{status}, vamf_body: #{body.inspect}}}"
    )
    exception
  end
end
