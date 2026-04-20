# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'VAOS::V2::UnifiedBookings#show', :skip_mvi, type: :request do
  let(:access_token) { 'fake-access-token' }
  let(:memory_store) { ActiveSupport::Cache.lookup_store(:memory_store) }
  let(:current_user) { build(:user, :vaos, icn: 'care-nav-patient-casey') }

  before do
    allow(Settings.mhv).to receive(:facility_range).and_return([[1, 999]])
    sign_in_as(current_user)
    allow_any_instance_of(VAOS::UserService).to receive(:session).and_return('stubbed_token')
    allow(Rails).to receive(:cache).and_return(memory_store)
    Rails.cache.write(Eps::BaseService::REDIS_TOKEN_KEY, access_token)

    Settings.vaos ||= OpenStruct.new
    Settings.vaos.eps ||= OpenStruct.new
    Settings.vaos.eps.tap do |eps|
      eps.api_url = 'https://api.wellhive.com'
    end

    allow(StatsD).to receive(:increment)
  end

  describe 'GET /vaos/v2/unified_bookings/:id' do
    context 'with provider_type=eps' do
      context 'with a booked appointment' do
        it 'returns the appointment with provider details' do
          VCR.use_cassette('vaos/eps/token/token_200', match_requests_on: %i[method path]) do
            VCR.use_cassette('vaos/eps/get_appointment/booked_200', match_requests_on: %i[method path]) do
              VCR.use_cassette('vaos/eps/providers/data_Aq7wgAux_200', match_requests_on: %i[method path]) do
                get '/vaos/v2/unified_bookings/qdm61cJ5', params: { provider_type: 'eps' }

                expect(response).to have_http_status(:ok)

                body = JSON.parse(response.body)
                data = body['data']

                expect(data['id']).to eq('qdm61cJ5')
                expect(data['type']).to eq('appointment')

                attrs = data['attributes']
                expect(attrs['id']).to eq('qdm61cJ5')
                expect(attrs['status']).to eq('booked')
                expect(attrs['careType']).to eq('CC')
                expect(attrs['start']).to eq('2024-11-21T18:00:00Z')
                expect(attrs['isLatest']).to be(true)
                expect(attrs['lastRetrieved']).to eq('2025-02-10T14:35:44Z')
                expect(attrs['referralId']).to eq('12345')
                expect(attrs['past']).to be(true)
                expect(attrs['modality']).to eq('communityCareUnified')
              end
            end
          end
        end

        it 'includes provider information' do
          VCR.use_cassette('vaos/eps/token/token_200', match_requests_on: %i[method path]) do
            VCR.use_cassette('vaos/eps/get_appointment/booked_200', match_requests_on: %i[method path]) do
              VCR.use_cassette('vaos/eps/providers/data_Aq7wgAux_200', match_requests_on: %i[method path]) do
                get '/vaos/v2/unified_bookings/qdm61cJ5', params: { provider_type: 'eps' }

                provider = JSON.parse(response.body).dig('data', 'attributes', 'provider')

                expect(provider['id']).to eq('test-provider-id')
                expect(provider['name']).to eq('Timothy Bob')
                expect(provider['practice']).to eq('test-provider-org-name')
                expect(provider['location']['name']).to eq('Test Medical Complex')
                expect(provider['location']['address']).to eq('207 Davishill Ln')
                expect(provider['location']['latitude']).to eq(33.058736)
                expect(provider['location']['longitude']).to eq(-80.032819)
                expect(provider['location']['timezone']).to eq('America/New_York')
              end
            end
          end
        end

        it 'includes location data with timezone' do
          VCR.use_cassette('vaos/eps/token/token_200', match_requests_on: %i[method path]) do
            VCR.use_cassette('vaos/eps/get_appointment/booked_200', match_requests_on: %i[method path]) do
              VCR.use_cassette('vaos/eps/providers/data_Aq7wgAux_200', match_requests_on: %i[method path]) do
                get '/vaos/v2/unified_bookings/qdm61cJ5', params: { provider_type: 'eps' }

                location = JSON.parse(response.body).dig('data', 'attributes', 'location')

                expect(location['id']).to be_present
                expect(location['type']).to eq('appointments')
                expect(location['attributes']['name']).to eq('Test Medical Complex')
                expect(location['attributes']['timezone']['timeZoneId']).to eq('America/New_York')
              end
            end
          end
        end
      end

      context 'with a draft appointment' do
        it 'returns the appointment without provider or location details' do
          VCR.use_cassette('vaos/eps/token/token_200', match_requests_on: %i[method path]) do
            VCR.use_cassette('vaos/eps/get_appointment/draft_200', match_requests_on: %i[method path]) do
              get '/vaos/v2/unified_bookings/qdm61cJ5', params: { provider_type: 'eps' }

              expect(response).to have_http_status(:ok)

              attrs = JSON.parse(response.body).dig('data', 'attributes')

              expect(attrs['status']).to eq('proposed')
              expect(attrs['careType']).to eq('CC')
              expect(attrs['modality']).to eq('communityCareUnified')
              expect(attrs).not_to have_key('provider')
              expect(attrs).not_to have_key('location')
            end
          end
        end
      end

      context 'when the appointment is not found' do
        it 'returns a 404 error' do
          VCR.use_cassette('vaos/eps/token/token_200', match_requests_on: %i[method path]) do
            VCR.use_cassette('vaos/eps/get_appointment/404', match_requests_on: %i[method path]) do
              get '/vaos/v2/unified_bookings/qdm61cJ5', params: { provider_type: 'eps' }

              expect(response).to have_http_status(:not_found)
            end
          end
        end
      end

      context 'when the upstream service returns a 500 error' do
        it 'returns a 502 error' do
          VCR.use_cassette('vaos/eps/token/token_200', match_requests_on: %i[method path]) do
            VCR.use_cassette('vaos/eps/get_appointment/500', match_requests_on: %i[method path]) do
              get '/vaos/v2/unified_bookings/qdm61cJ5', params: { provider_type: 'eps' }

              expect(response).to have_http_status(:bad_gateway)
            end
          end
        end
      end

      context 'when the provider fetch fails' do
        it 'still returns the appointment without provider details' do
          VCR.use_cassette('vaos/eps/token/token_200', match_requests_on: %i[method path]) do
            VCR.use_cassette('vaos/eps/get_appointment/booked_200', match_requests_on: %i[method path]) do
              allow_any_instance_of(Eps::ProviderService).to receive(:get_provider_service)
                .and_raise(Common::Exceptions::BackendServiceException.new('VAOS_502'))
              allow(Rails.logger).to receive(:error)

              get '/vaos/v2/unified_bookings/qdm61cJ5', params: { provider_type: 'eps' }

              expect(response).to have_http_status(:ok)
              attrs = JSON.parse(response.body).dig('data', 'attributes')
              expect(attrs['status']).to eq('booked')
              expect(attrs['provider']).to be_nil
            end
          end
        end
      end
    end

    context 'with provider_type=va' do
      let(:mock_appointments_service) { instance_double(VAOS::V2::AppointmentsService) }
      let(:mock_va_appointment) do
        OpenStruct.new(
          id: 'va-appt-001',
          status: 'booked',
          start: '2026-04-15T14:00:00Z',
          past: false,
          modality: 'vaInPerson',
          service_name: 'CHY PC CASSIDY',
          location: {
            'id' => '983GB',
            'name' => 'Cheyenne VA Medical Center',
            'timezone' => { 'zoneId' => 'America/Denver' },
            'lat' => 39.744507,
            'long' => -104.830956,
            'phone' => { 'main' => '307-778-7550' },
            'physicalAddress' => {
              'line' => ['2360 East Pershing Boulevard'],
              'city' => 'Cheyenne',
              'state' => 'WY',
              'postalCode' => '82001-5356'
            }
          }
        )
      end

      before do
        allow(VAOS::V2::AppointmentsService).to receive(:new).and_return(mock_appointments_service)
        allow(mock_appointments_service).to receive(:get_appointment).and_return(mock_va_appointment)
      end

      it 'returns the VA appointment in the unified format' do
        get '/vaos/v2/unified_bookings/va-appt-001', params: { provider_type: 'va' }

        expect(response).to have_http_status(:ok)

        body = JSON.parse(response.body)
        data = body['data']

        expect(data['id']).to eq('va-appt-001')
        expect(data['type']).to eq('appointment')

        attrs = data['attributes']
        expect(attrs['status']).to eq('booked')
        expect(attrs['careType']).to eq('VA')
        expect(attrs['start']).to eq('2026-04-15T14:00:00Z')
        expect(attrs['past']).to be(false)
        expect(attrs['modality']).to eq('vaInPerson')
      end

      it 'maps facility + clinic to the provider field' do
        get '/vaos/v2/unified_bookings/va-appt-001', params: { provider_type: 'va' }

        provider = JSON.parse(response.body).dig('data', 'attributes', 'provider')

        expect(provider['name']).to eq('CHY PC CASSIDY')
        expect(provider['practice']).to eq('Cheyenne VA Medical Center')
        expect(provider['phone']).to eq('307-778-7550')
        expect(provider['location']['name']).to eq('Cheyenne VA Medical Center')
        expect(provider['location']['address']).to eq('2360 East Pershing Boulevard, Cheyenne, WY, 82001-5356')
        expect(provider['location']['latitude']).to eq(39.744507)
        expect(provider['location']['longitude']).to eq(-104.830956)
        expect(provider['location']['timezone']).to eq('America/Denver')
      end

      it 'does not include a redundant top-level location (info is in provider.location)' do
        get '/vaos/v2/unified_bookings/va-appt-001', params: { provider_type: 'va' }

        attrs = JSON.parse(response.body).dig('data', 'attributes')
        expect(attrs).not_to have_key('location')
      end

      it 'calls the VAOS appointments service with the correct id' do
        get '/vaos/v2/unified_bookings/va-appt-001', params: { provider_type: 'va' }

        expect(mock_appointments_service).to have_received(:get_appointment).with('va-appt-001', {})
      end

      context 'when facility fetch failed during get_appointment' do
        let(:mock_va_appointment_no_facility) do
          OpenStruct.new(
            id: 'va-appt-002',
            status: 'booked',
            start: '2026-04-15T14:00:00Z',
            past: false,
            modality: 'vaInPerson',
            location_id: '983',
            location: nil
          )
        end

        before do
          allow(mock_appointments_service).to receive(:get_appointment)
            .and_return(mock_va_appointment_no_facility)
        end

        it 'returns ok with facilityError and omits provider' do
          get '/vaos/v2/unified_bookings/va-appt-002', params: { provider_type: 'va' }

          expect(response).to have_http_status(:ok)

          attrs = JSON.parse(response.body).dig('data', 'attributes')
          expect(attrs['facilityError']).to eq('Error fetching facility details')
          expect(attrs['provider']).to be_nil
        end
      end

      context 'when VAOS upstream service fails' do
        before do
          allow(mock_appointments_service).to receive(:get_appointment)
            .and_raise(Common::Exceptions::BackendServiceException.new('VAOS_502'))
        end

        it 'returns a 502 error' do
          get '/vaos/v2/unified_bookings/va-appt-001', params: { provider_type: 'va' }

          expect(response).to have_http_status(:bad_gateway)
        end
      end
    end

    context 'with invalid provider_type' do
      it 'returns 400' do
        get '/vaos/v2/unified_bookings/some-id', params: { provider_type: 'invalid' }

        expect(response).to have_http_status(:bad_request)
      end
    end

    context 'without provider_type' do
      it 'returns 400' do
        get '/vaos/v2/unified_bookings/some-id'

        expect(response).to have_http_status(:bad_request)
      end
    end

    context 'when user is not LOA3' do
      let(:current_user) { build(:user, :loa1) }

      it 'returns 403' do
        get '/vaos/v2/unified_bookings/qdm61cJ5', params: { provider_type: 'eps' }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
