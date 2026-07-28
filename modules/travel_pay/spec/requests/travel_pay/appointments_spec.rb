# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TravelPay::V0::AppointmentsController, type: :request do
  let(:user) { build(:user) }
  let(:appointment) do
    {
      'id' => '3fa85f64-5717-4562-b3fc-2c963f66afa6',
      'appointmentSource' => 'API',
      'appointmentDateTime' => '2026-04-30T15:33:58.570Z',
      'appointmentName' => 'Test Appointment',
      'appointmentType' => 'EnvironmentalHealth',
      'facilityId' => '3fa85f64-5717-4562-b3fc-2c963f66afa6',
      'facilityName' => 'Test Facility',
      'serviceConnectedDisability' => 0,
      'currentStatus' => 'Active',
      'appointmentStatus' => 'Active',
      'externalAppointmentId' => 'ext-123',
      'associatedClaimId' => nil,
      'associatedClaimNumber' => nil,
      'isCompleted' => false
    }
  end

  before do
    sign_in(user)
    allow(Flipper).to receive(:enabled?).with(:travel_pay_power_switch, instance_of(User)).and_return(true)
    allow(Flipper).to receive(:enabled?).with(:travel_pay_enable_user_created_appointments,
                                              instance_of(User)).and_return(true)
    allow(Flipper).to receive(:enabled?).with(:travel_pay_unified_error_handling, instance_of(User)).and_return(true)

    auth_manager_double = instance_double(
      TravelPay::AuthManager,
      authorize: TravelPay::AuthSession.new(veis_token: 'vt', btsss_token: 'bt'),
      user:
    )
    allow(TravelPay::AuthManager).to receive(:new).and_return(auth_manager_double)
  end

  describe 'GET #index' do
    context 'when the user-created appointments feature flag is enabled' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(:travel_pay_enable_user_created_appointments, instance_of(User))
          .and_return(true)
      end

      context 'when appointments are found' do
        before do
          allow_any_instance_of(TravelPay::AppointmentsService)
            .to receive(:search_appointments)
            .and_return([appointment])
        end

        it 'returns 200 with an array of appointments' do
          params = { appointment_start_date: '2026-04-01T00:00:00Z', appointment_end_date: '2026-04-30T23:59:59Z' }

          get '/travel_pay/v0/appointments/search',
              params:,
              headers: { 'Authorization' => 'Bearer vagov_token' }

          expect(response).to have_http_status(:ok)
          body = JSON.parse(response.body)
          expect(body['data'].length).to eq(1)
          expect(body['data'].first['id']).to eq('3fa85f64-5717-4562-b3fc-2c963f66afa6')
        end
      end

      context 'when no appointments are found' do
        before do
          allow_any_instance_of(TravelPay::AppointmentsService)
            .to receive(:search_appointments)
            .and_return([])
        end

        it 'returns 200 with an empty data array' do
          get '/travel_pay/v0/appointments/search',
              headers: { 'Authorization' => 'Bearer vagov_token' }

          expect(response).to have_http_status(:ok)
          body = JSON.parse(response.body)
          expect(body['data']).to eq([])
        end
      end

      context 'when the upstream API returns a 5xx error' do
        [
          [500, :bad_gateway],
          [502, :bad_gateway],
          [503, :service_unavailable],
          [504, :gateway_timeout]
        ].each do |upstream_status, expected_status|
          it "maps upstream #{upstream_status} to #{expected_status}" do
            allow_any_instance_of(TravelPay::AppointmentsService)
              .to receive(:search_appointments)
              .and_raise(Common::Exceptions::BackendServiceException.new("BTSSS-API_#{upstream_status}",
                                                                         { status: upstream_status },
                                                                         upstream_status))

            get '/travel_pay/v0/appointments/search',
                headers: { 'Authorization' => 'Bearer vagov_token' }

            expect(response).to have_http_status(expected_status)
            body = JSON.parse(response.body)
            expect(body['errors']).to be_present
            expect(body['errors'].first['code']).to eq("BTSSS-API_#{upstream_status}")
          end
        end
      end
    end

    context 'when the user-created appointments feature flag is disabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:travel_pay_enable_user_created_appointments,
                                                  instance_of(User)).and_return(false)
      end

      it 'returns 503 service unavailable' do
        get '/travel_pay/v0/appointments/search',
            headers: { 'Authorization' => 'Bearer vagov_token' }

        expect(response).to have_http_status(:service_unavailable)
      end
    end
  end

  describe 'POST #create' do
    let(:appointment_id) { '3fa85f64-5717-4562-b3fc-2c963f66afa6' }
    let(:create_params) do
      {
        facility_id: appointment_id,
        appointment_name: 'Dermatology appointment',
        appointment_date_time: '2026-03-31T08:00:00Z',
        completed: true
      }
    end

    context 'when the user-created appointments feature flag is enabled' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(:travel_pay_enable_user_created_appointments, instance_of(User))
          .and_return(true)
      end

      context 'when the appointment is successfully created' do
        before do
          allow_any_instance_of(TravelPay::AppointmentsService)
            .to receive(:create_appointment)
            .and_return({ 'appointmentId' => appointment_id })
        end

        it 'returns 201 with the new appointment ID' do
          post '/travel_pay/v0/appointments',
               params: create_params,
               headers: { 'Authorization' => 'Bearer vagov_token' }

          expect(response).to have_http_status(:created)
          body = JSON.parse(response.body)
          expect(body['data']['appointmentId']).to eq(appointment_id)
        end
      end

      context 'when the upstream API returns a 5xx error' do
        [
          [500, :bad_gateway],
          [502, :bad_gateway],
          [503, :service_unavailable],
          [504, :gateway_timeout]
        ].each do |upstream_status, expected_status|
          it "maps upstream #{upstream_status} to #{expected_status}" do
            allow_any_instance_of(TravelPay::AppointmentsService)
              .to receive(:create_appointment)
              .and_raise(Common::Exceptions::BackendServiceException.new("BTSSS-API_#{upstream_status}",
                                                                         { status: upstream_status },
                                                                         upstream_status))

            post '/travel_pay/v0/appointments',
                 params: create_params,
                 headers: { 'Authorization' => 'Bearer vagov_token' }

            expect(response).to have_http_status(expected_status)
            body = JSON.parse(response.body)
            expect(body['errors']).to be_present
            expect(body['errors'].first['code']).to eq("BTSSS-API_#{upstream_status}")
          end
        end
      end

      context 'when a Faraday connection error occurs' do
        it 'returns 503 with BTSSS error code' do
          allow_any_instance_of(TravelPay::AppointmentsService)
            .to receive(:create_appointment)
            .and_raise(Faraday::ConnectionFailed.new('Failed to connect'))

          post '/travel_pay/v0/appointments',
               params: create_params,
               headers: { 'Authorization' => 'Bearer vagov_token' }

          expect(response).to have_http_status(:service_unavailable)
          body = JSON.parse(response.body)
          expect(body['errors'].first['code']).to eq('BTSSS-API_CONNECTION_FAILED')
        end
      end

      context 'when a Faraday timeout occurs' do
        it 'returns 504 with BTSSS timeout error code' do
          allow_any_instance_of(TravelPay::AppointmentsService)
            .to receive(:create_appointment)
            .and_raise(Faraday::TimeoutError)

          post '/travel_pay/v0/appointments',
               params: create_params,
               headers: { 'Authorization' => 'Bearer vagov_token' }

          expect(response).to have_http_status(:gateway_timeout)
          body = JSON.parse(response.body)
          expect(body['errors'].first['code']).to eq('BTSSS-API_CONNECTION_TIMEOUT')
        end
      end

      context 'when a Faraday client error with upstream status occurs' do
        it 'returns the upstream status with the matching BTSSS code' do
          error = Faraday::ClientError.new('Bad request', { status: 400, body: 'invalid' })
          allow_any_instance_of(TravelPay::AppointmentsService)
            .to receive(:create_appointment)
            .and_raise(error)

          post '/travel_pay/v0/appointments',
               params: create_params,
               headers: { 'Authorization' => 'Bearer vagov_token' }

          expect(response).to have_http_status(:bad_request)
          body = JSON.parse(response.body)
          expect(body['errors'].first['code']).to eq('BTSSS-API_400')
        end
      end
    end

    context 'when the user-created appointments feature flag is disabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:travel_pay_enable_user_created_appointments,
                                                  instance_of(User)).and_return(false)
      end

      it 'returns 503 and logs the error' do
        allow(Rails.logger).to receive(:error)
        expect(Rails.logger).to receive(:error)
          .with(message: 'Travel Pay user-created appointments endpoint unavailable per feature toggle')

        post '/travel_pay/v0/appointments',
             params: create_params,
             headers: { 'Authorization' => 'Bearer vagov_token' }

        expect(response).to have_http_status(:service_unavailable)
      end
    end
  end

  context 'with unified error handling disabled (legacy)' do
    before do
      allow(Flipper).to receive(:enabled?).with(:travel_pay_unified_error_handling,
                                                instance_of(User)).and_return(false)
    end

    describe 'GET #index' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(:travel_pay_enable_user_created_appointments, instance_of(User))
          .and_return(true)
      end

      it 'renders legacy error response for BackendServiceException' do
        allow_any_instance_of(TravelPay::AppointmentsService)
          .to receive(:search_appointments)
          .and_raise(Common::Exceptions::BackendServiceException.new(nil, { detail: 'upstream error' }, 503))

        get '/travel_pay/v0/appointments/search',
            headers: { 'Authorization' => 'Bearer vagov_token' }

        expect(response).to have_http_status(:service_unavailable)
        body = JSON.parse(response.body)
        expect(body['error']).to eq('Error searching appointments')
      end
    end

    describe 'POST #create' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(:travel_pay_enable_user_created_appointments, instance_of(User))
          .and_return(true)
      end

      it 'renders legacy error response for BackendServiceException' do
        allow_any_instance_of(TravelPay::AppointmentsService)
          .to receive(:create_appointment)
          .and_raise(Common::Exceptions::BackendServiceException.new(nil, { detail: 'upstream error' }, 500))

        post '/travel_pay/v0/appointments',
             params: { facility_id: 'abc', appointment_name: 'test',
                       appointment_date_time: '2026-03-31T08:00:00Z', completed: true },
             headers: { 'Authorization' => 'Bearer vagov_token' }

        expect(response).to have_http_status(:internal_server_error)
        body = JSON.parse(response.body)
        expect(body['error']).to eq('Error creating appointment')
      end
    end
  end
end
