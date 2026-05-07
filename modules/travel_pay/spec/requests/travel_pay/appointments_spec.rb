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

    auth_manager_double = instance_double(
      TravelPay::AuthManager,
      authorize: TravelPay::AuthSession.new(veis_token: 'vt', btsss_token: 'bt'),
      user:
    )
    allow(TravelPay::AuthManager).to receive(:new).and_return(auth_manager_double)
  end

  describe 'GET #index' do
    context 'when the user-created appointments feature flag is enabled' do
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
          [500, :internal_server_error],
          [502, :bad_gateway],
          [503, :service_unavailable],
          [504, :gateway_timeout]
        ].each do |status_code, expected_status|
          it "maps upstream #{status_code} to #{expected_status}" do
            allow_any_instance_of(TravelPay::AppointmentsService)
              .to receive(:search_appointments)
              .and_raise(Faraday::ServerError.new(nil,
                                                  { status: status_code, body: { 'message' => 'upstream error' } }))

            get '/travel_pay/v0/appointments/search',
                headers: { 'Authorization' => 'Bearer vagov_token' }

            expect(response).to have_http_status(expected_status)
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
end
