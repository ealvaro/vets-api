# frozen_string_literal: true

require 'rails_helper'

describe TravelPay::AppointmentsService do
  context 'get_appointment_by_date_time' do
    let(:user) { build(:user) }
    let(:appointments_data) do
      {
        'data' => [
          {
            'id' => 'uuid1',
            'appointmentSource' => 'API',
            'appointmentDateTime' => '2024-01-01T16:45:34.465Z',
            'appointmentName' => 'string',
            'appointmentType' => 'EnvironmentalHealth',
            'facilityName' => 'Cheyenne VA Medical Center',
            'serviceConnectedDisability' => 30,
            'currentStatus' => 'string',
            'appointmentStatus' => 'Completed',
            'externalAppointmentId' => '12345678-0000-0000-0000-000000000001',
            'associatedClaimId' => nil,
            'associatedClaimNumber' => nil,
            'isCompleted' => true
          },
          {
            'id' => 'uuid2',
            'appointmentSource' => 'API',
            'appointmentDateTime' => '2024-03-01T16:45:34.465Z',
            'appointmentName' => 'string',
            'appointmentType' => 'EnvironmentalHealth',
            'facilityName' => 'Cheyenne VA Medical Center',
            'serviceConnectedDisability' => 30,
            'currentStatus' => 'string',
            'appointmentStatus' => 'Completed',
            'externalAppointmentId' => '12345678-0000-0000-0000-000000000002',
            'associatedClaimId' => nil,
            'associatedClaimNumber' => nil,
            'isCompleted' => true
          },
          {
            'id' => 'uuid3',
            'appointmentSource' => 'API',
            'appointmentDateTime' => '2024-01-01T12:45:34.465Z',
            'appointmentName' => 'string',
            'appointmentType' => 'EnvironmentalHealth',
            'facilityName' => 'Cheyenne VA Medical Center',
            'serviceConnectedDisability' => 30,
            'currentStatus' => 'string',
            'appointmentStatus' => 'Completed',
            'externalAppointmentId' => '12345678-0000-0000-0000-000000000003',
            'associatedClaimId' => nil,
            'associatedClaimNumber' => nil,
            'isCompleted' => true
          },
          {
            'id' => 'uuid4',
            'appointmentSource' => 'API',
            'appointmentDateTime' => nil,
            'appointmentName' => 'string',
            'appointmentType' => 'EnvironmentalHealth',
            'facilityName' => 'Cheyenne VA Medical Center',
            'serviceConnectedDisability' => 30,
            'currentStatus' => 'string',
            'appointmentStatus' => 'Completed',
            'externalAppointmentId' => '12345678-0000-0000-0000-000000000004',
            'associatedClaimId' => nil,
            'associatedClaimNumber' => nil,
            'isCompleted' => true
          }
        ]
      }
    end
    let(:appointments_response) do
      Faraday::Response.new(
        body: appointments_data
      )
    end

    let(:auth_session) { TravelPay::AuthSession.new(veis_token: 'veis_token', btsss_token: 'btsss_token', contact_id: 'contact_id') }
    let(:auth_manager) { object_double(TravelPay::AuthManager.new(123, user), authorize: auth_session, user:) }
    let(:service) { TravelPay::AppointmentsService.new(auth_manager) }

    before do
      allow_any_instance_of(TravelPay::AppointmentsClient)
        .to receive(:get_all_appointments)
        .with(auth_session, { 'excludeWithClaims' => true })
        .and_return(appointments_response)
    end

    context 'find by appt date-time' do
      it 'returns the BTSSS appointment that matches appt date' do
        date_string = '2024-01-01T12:45:34.465Z'
        appt = service.get_appointment_by_date_time({ 'appt_datetime' => date_string })

        expect(appt[:data]['appointmentDateTime']).to eq(date_string)
      end

      it 'returns nil if appt date does not match' do
        appt = service.get_appointment_by_date_time({ 'appt_datetime' => '1700-01-01T12:45:34.465Z' })

        expect(appt[:data]).to equal(nil)
      end

      it 'throws an Argument Error if appt date is invalid' do
        expect { service.get_appointment_by_date_time({ 'appt_datetime' => 'banana' }) }
          .to raise_error(ArgumentError, /Invalid appointment time/i)

        expect { service.get_appointment_by_date_time({ 'appt_datetime' => nil }) }
          .to raise_error(ArgumentError, /Invalid appointment time/i)
      end
    end
  end

  context 'search_appointments' do
    let(:user) { build(:user) }
    let(:auth_session) { TravelPay::AuthSession.new(veis_token: 'veis_token', btsss_token: 'btsss_token') }
    let(:auth_manager) { object_double(TravelPay::AuthManager.new(123, user), authorize: auth_session, user:) }
    let(:service) { TravelPay::AppointmentsService.new(auth_manager) }
    let(:appointment_data) do
      [
        {
          'id' => 'uuid1',
          'appointmentDateTime' => '2026-04-15T10:00:00Z',
          'facilityName' => 'Cheyenne VA Medical Center',
          'isCompleted' => false
        }
      ]
    end

    context 'when the client returns appointments' do
      let(:search_response) { Faraday::Response.new(body: { 'data' => appointment_data }) }

      before do
        allow_any_instance_of(TravelPay::AppointmentsClient)
          .to receive(:search_appointments)
          .and_return(search_response)
      end

      it 'returns the data array' do
        result = service.search_appointments({ 'appointment_start_date' => '2026-04-01T00:00:00Z' })

        expect(result).to eq(appointment_data)
      end
    end

    context 'when the client returns no data' do
      let(:empty_response) { Faraday::Response.new(body: {}) }

      before do
        allow_any_instance_of(TravelPay::AppointmentsClient)
          .to receive(:search_appointments)
          .and_return(empty_response)
      end

      it 'returns an empty array' do
        result = service.search_appointments({})

        expect(result).to eq([])
      end
    end
  end

  context 'find or create appointment' do
    let(:user) { build(:user) }

    let(:add_appointment_response) do
      Faraday::Response.new(
        body: {
          'data' => [
            {
              'id' => 'uuid1',
              'appointmentSource' => 'API',
              'appointmentDateTime' => '2024-01-01T16:45:34.465Z',
              'appointmentName' => 'string',
              'appointmentType' => 'EnvironmentalHealth',
              'facilityName' => 'Cheyenne VA Medical Center',
              'serviceConnectedDisability' => 30,
              'currentStatus' => 'string',
              'appointmentStatus' => 'Completed',
              'externalAppointmentId' => '12345678-0000-0000-0000-000000000001',
              'associatedClaimId' => nil,
              'associatedClaimNumber' => nil,
              'isCompleted' => true
            }
          ]
        }
      )
    end

    let(:auth_session) { TravelPay::AuthSession.new(veis_token: 'veis_token', btsss_token: 'btsss_token', contact_id: 'contact_id') }
    let(:auth_manager) { object_double(TravelPay::AuthManager.new(123, user), authorize: auth_session, user:) }
    let(:service) { TravelPay::AppointmentsService.new(auth_manager) }

    context 'when travel_pay_appt_add_v4_upgrade feature flag is disabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:travel_pay_appt_add_v4_upgrade, user).and_return(false)
        allow_any_instance_of(TravelPay::AppointmentsClient)
          .to receive(:find_or_create)
          .with(auth_session,
                { 'appointment_date_time' => '2024-01-01T12:45:00',
                  'facility_station_number' => '123',
                  'appointment_type' => 'Other',
                  'is_complete' => false }, use_v4_api: false)
          .and_return(add_appointment_response)
      end

      it 'returns the BTSSS appointment that matches appt date' do
        date_string = '2024-01-01T12:45:00'

        params = { 'appointment_date_time' => date_string,
                   'facility_station_number' => '123',
                   'appointment_type' => 'Other',
                   'is_complete' => false }

        appt = service.find_or_create_appointment(params)

        expect(appt[:data]['id']).to eq('uuid1')
      end

      it 'calls find_or_create with use_v4_api = false' do
        date_string = '2024-01-01T12:45:00'

        params = { 'appointment_date_time' => date_string,
                   'facility_station_number' => '123',
                   'appointment_type' => 'Other',
                   'is_complete' => false }

        expect_any_instance_of(TravelPay::AppointmentsClient)
          .to receive(:find_or_create)
          .with(auth_session,
                { 'appointment_date_time' => '2024-01-01T12:45:00',
                  'facility_station_number' => '123',
                  'appointment_type' => 'Other',
                  'is_complete' => false }, use_v4_api: false)
          .and_return(add_appointment_response)

        service.find_or_create_appointment(params)
      end

      it 'throws an Argument Error if appt date is invalid' do
        expect do
          service.find_or_create_appointment({ 'appointment_date_time' => 'banana',
                                               'facility_station_number' => '123',
                                               'appointment_type' => 'Other',
                                               'is_complete' => false })
        end
          .to raise_error(ArgumentError, /Invalid appointment time/i)

        expect do
          service.find_or_create_appointment({ 'appointment_date_time' => nil,
                                               'facility_station_number' => '123',
                                               'appointment_type' => 'Other',
                                               'is_complete' => false })
        end
          .to raise_error(ArgumentError, /Invalid appointment time/i)
      end
    end

    context 'when travel_pay_appt_add_v4_upgrade feature flag is enabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:travel_pay_appt_add_v4_upgrade, user).and_return(true)
        allow_any_instance_of(TravelPay::AppointmentsClient)
          .to receive(:find_or_create)
          .with(auth_session,
                { 'appointment_date_time' => '2024-01-01T12:45:00',
                  'facility_station_number' => '123',
                  'appointment_type' => 'Other',
                  'is_complete' => false,
                  'appointment_name' => 'Test Appointment Name',
                  'facility_name' => 'Test facility' }, use_v4_api: true)
          .and_return(add_appointment_response)
      end

      it 'calls find_or_create with use_v4_api = true' do
        date_string = '2024-01-01T12:45:00'

        params = { 'appointment_date_time' => date_string,
                   'facility_station_number' => '123',
                   'appointment_type' => 'Other',
                   'is_complete' => false,
                   'appointment_name' => 'Test Appointment Name',
                   'facility_name' => 'Test facility' }

        appt = service.find_or_create_appointment(params)

        expect(appt[:data]['id']).to eq('uuid1')
      end

      it 'raises a BadRequest if facility_name is missing' do
        params = { 'appointment_date_time' => '2024-01-01T12:45:00',
                   'facility_station_number' => '123',
                   'appointment_type' => 'Other',
                   'is_complete' => false,
                   'appointment_name' => 'Test Appointment Name' }

        expect { service.find_or_create_appointment(params) }
          .to raise_error(Common::Exceptions::BadRequest)
      end

      it 'raises a BadRequest if facility_name is an empty string' do
        params = { 'appointment_date_time' => '2024-01-01T12:45:00',
                   'facility_station_number' => '123',
                   'appointment_type' => 'Other',
                   'is_complete' => false,
                   'appointment_name' => 'Test Appointment Name',
                   'facility_name' => '' }

        expect { service.find_or_create_appointment(params) }
          .to raise_error(Common::Exceptions::BadRequest)
      end
    end
  end

  context 'create_appointment' do
    let(:user) { build(:user) }
    let(:auth_session) { TravelPay::AuthSession.new(veis_token: 'veis_token', btsss_token: 'btsss_token') }
    let(:auth_manager) { object_double(TravelPay::AuthManager.new(123, user), authorize: auth_session, user:) }
    let(:service) { TravelPay::AppointmentsService.new(auth_manager) }
    let(:appointment_id) { '3fa85f64-5717-4562-b3fc-2c963f66afa6' }
    let(:create_params) do
      {
        'facility_id' => appointment_id,
        'appointment_name' => 'Dermatology appointment',
        'appointment_date_time' => '2026-03-31T08:00:00Z',
        'completed' => true
      }
    end
    let(:params_with_type) { create_params.merge('appointment_type' => 'Care') }

    it 'merges appointment_type Care and returns the data object from the client response' do
      response_data = { 'appointmentId' => appointment_id }
      faraday_response = Faraday::Response.new(body: { 'data' => response_data })

      allow_any_instance_of(TravelPay::AppointmentsClient)
        .to receive(:create_appointment)
        .with(auth_session, params_with_type)
        .and_return(faraday_response)

      result = service.create_appointment(create_params)
      expect(result).to eq(response_data)
    end
  end
end
