# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'VAOS::V2::UnifiedBookings', :skip_mvi, type: :request do
  before do
    allow(Settings.mhv).to receive(:facility_range).and_return([[1, 999]])
    sign_in_as(current_user)
    allow_any_instance_of(VAOS::UserService).to receive(:session).and_return('stubbed_token')
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:warn)
    allow(Rails.logger).to receive(:error)
    allow(StatsD).to receive(:increment)
  end

  let(:current_user) { build(:user, :vaos) }

  describe 'POST /vaos/v2/unified_bookings' do
    let(:headers) { { 'Content-Type' => 'application/json', 'Accept' => 'application/json' } }

    context 'with a VA provider' do
      let(:va_params) do
        {
          provider_type: 'va',
          slot_id: 'slot-encoded-id-123',
          location_id: '983',
          clinic_id: '455',
          service_type: 'primaryCare'
        }
      end

      let(:mock_appointments_service) { instance_double(VAOS::V2::AppointmentsService) }

      let(:mock_va_response) do
        OpenStruct.new(
          id: 'va-appt-001',
          status: 'booked',
          start: '2026-04-15T14:00:00Z'
        )
      end

      before do
        allow(VAOS::V2::AppointmentsService).to receive(:new).and_return(mock_appointments_service)
        allow(mock_appointments_service).to receive(:post_appointment).and_return(mock_va_response)
      end

      it 'creates a VA appointment and returns confirmation' do
        post('/vaos/v2/unified_bookings', params: va_params.to_json, headers:)

        expect(response).to have_http_status(:created)

        body = JSON.parse(response.body)
        expect(body['data']['id']).to eq('va-appt-001')
        expect(body['data']['type']).to eq('unified_booking')
        expect(body['data']['attributes']['provider_type']).to eq('va')
        expect(body['data']['attributes']['status']).to eq('booked')
        expect(body['data']['attributes']['start']).to eq('2026-04-15T14:00:00Z')
      end

      it 'builds the correct VAOS request body' do
        post('/vaos/v2/unified_bookings', params: va_params.to_json, headers:)

        expect(mock_appointments_service).to have_received(:post_appointment).with(
          hash_including(
            kind: 'clinic',
            status: 'booked',
            location_id: '983',
            clinic: '455',
            slot: { id: 'slot-encoded-id-123' },
            service_type: 'primaryCare'
          )
        )
      end

      it 'returns 400 when location_id is missing' do
        post('/vaos/v2/unified_bookings',
             params: va_params.except(:location_id).to_json,
             headers:)

        expect(response).to have_http_status(:bad_request)
      end

      it 'returns 400 when slot_id is missing' do
        post('/vaos/v2/unified_bookings',
             params: va_params.except(:slot_id).to_json,
             headers:)

        expect(response).to have_http_status(:bad_request)
      end

      it 'returns 400 when clinic_id is missing' do
        post('/vaos/v2/unified_bookings',
             params: va_params.except(:clinic_id).to_json,
             headers:)

        expect(response).to have_http_status(:bad_request)
      end

      it 'returns 400 when service_type is missing' do
        post('/vaos/v2/unified_bookings',
             params: va_params.except(:service_type).to_json,
             headers:)

        expect(response).to have_http_status(:bad_request)
      end

      it 'returns 400 when service_type is blank' do
        post('/vaos/v2/unified_bookings',
             params: va_params.merge(service_type: '').to_json,
             headers:)

        expect(response).to have_http_status(:bad_request)
      end

      it 'passes the requested service_type through to the VAOS request body' do
        post('/vaos/v2/unified_bookings',
             params: va_params.merge(service_type: 'optometry').to_json,
             headers:)

        expect(response).to have_http_status(:created)
        expect(mock_appointments_service).to have_received(:post_appointment).with(
          hash_including(service_type: 'optometry')
        )
      end

      context 'when VAOS upstream service fails' do
        before do
          allow(mock_appointments_service).to receive(:post_appointment)
            .and_raise(Common::Exceptions::BackendServiceException.new('VAOS_502'))
        end

        it 'returns a 502 error response' do
          post('/vaos/v2/unified_bookings', params: va_params.to_json, headers:)

          expect(response).to have_http_status(:bad_gateway)
          body = JSON.parse(response.body)
          expect(body['errors']).to be_present
        end
      end

      context 'when VAOS returns a booked response without an appointment id' do
        before do
          allow(mock_appointments_service).to receive(:post_appointment)
            .and_return(OpenStruct.new(status: 'booked'))
        end

        it 'returns 502' do
          post('/vaos/v2/unified_bookings', params: va_params.to_json, headers:)

          expect(response).to have_http_status(:bad_gateway)
          body = JSON.parse(response.body)
          expect(body['errors']).to be_present
        end
      end
    end

    context 'with an EPS provider' do
      let(:eps_params) do
        {
          provider_type: 'eps',
          slot_id: 'eps-slot-xyz|prov|2026-04-15T10:00:00Z|30m0s',
          provider_service_id: 'prov-789',
          network_id: 'sandbox-net-1',
          referral_number: 'VA0000005678'
        }
      end

      let(:mock_eps_service) { instance_double(Eps::AppointmentService) }

      let(:mock_draft_response) { OpenStruct.new(id: 'draft-001', state: 'draft') }

      let(:mock_submit_response) do
        OpenStruct.new(id: 'draft-001', state: 'booked', start: '2026-04-15T10:00:00Z')
      end

      before do
        allow(Eps::AppointmentService).to receive(:new).and_return(mock_eps_service)
        allow(mock_eps_service).to receive_messages(create_draft_appointment: mock_draft_response,
                                                    submit_appointment: mock_submit_response)
      end

      it 'creates draft, submits, and returns confirmation' do
        post('/vaos/v2/unified_bookings', params: eps_params.to_json, headers:)

        expect(response).to have_http_status(:created)

        body = JSON.parse(response.body)
        expect(body['data']['id']).to eq('draft-001')
        expect(body['data']['type']).to eq('unified_booking')
        expect(body['data']['attributes']['provider_type']).to eq('eps')
        expect(body['data']['attributes']['status']).to eq('booked')
      end

      it 'calls create_draft then submit_appointment' do
        post('/vaos/v2/unified_bookings', params: eps_params.to_json, headers:)

        expect(mock_eps_service).to have_received(:create_draft_appointment)
          .with(referral_id: 'VA0000005678')
        expect(mock_eps_service).to have_received(:submit_appointment)
          .with('draft-001', hash_including(
                               network_id: 'sandbox-net-1',
                               provider_service_id: 'prov-789',
                               referral_number: 'VA0000005678'
                             ))
      end

      it 'returns 400 when provider_service_id is missing' do
        post('/vaos/v2/unified_bookings',
             params: eps_params.except(:provider_service_id).to_json,
             headers:)

        expect(response).to have_http_status(:bad_request)
      end

      it 'returns 400 when slot_id is missing' do
        post('/vaos/v2/unified_bookings',
             params: eps_params.except(:slot_id).to_json,
             headers:)

        expect(response).to have_http_status(:bad_request)
      end

      it 'returns 400 when referral_number is missing' do
        post('/vaos/v2/unified_bookings',
             params: eps_params.except(:referral_number).to_json,
             headers:)

        expect(response).to have_http_status(:bad_request)
      end

      it 'returns 400 when network_id is missing' do
        post('/vaos/v2/unified_bookings',
             params: eps_params.except(:network_id).to_json,
             headers:)

        expect(response).to have_http_status(:bad_request)
      end

      context 'when EPS draft creation fails' do
        before do
          allow(mock_eps_service).to receive(:create_draft_appointment)
            .and_raise(Common::Exceptions::BackendServiceException.new('VAOS_502'))
        end

        it 'returns a 502 error response' do
          post('/vaos/v2/unified_bookings', params: eps_params.to_json, headers:)

          expect(response).to have_http_status(:bad_gateway)
          body = JSON.parse(response.body)
          expect(body['errors']).to be_present
        end
      end

      context 'when EPS draft response has no appointment id' do
        before do
          allow(mock_eps_service).to receive(:create_draft_appointment)
            .and_return(OpenStruct.new(state: 'draft'))
        end

        it 'returns 502' do
          post('/vaos/v2/unified_bookings', params: eps_params.to_json, headers:)

          expect(response).to have_http_status(:bad_gateway)
          body = JSON.parse(response.body)
          expect(body['errors']).to be_present
        end
      end

      context 'when EPS submit response has no appointment id' do
        before do
          allow(mock_eps_service).to receive(:submit_appointment)
            .and_return(OpenStruct.new(state: 'booked'))
        end

        it 'returns 502' do
          post('/vaos/v2/unified_bookings', params: eps_params.to_json, headers:)

          expect(response).to have_http_status(:bad_gateway)
          body = JSON.parse(response.body)
          expect(body['errors']).to be_present
        end
      end
    end

    context 'with an invalid provider_type' do
      it 'returns 400' do
        post('/vaos/v2/unified_bookings',
             params: { provider_type: 'invalid', slot_id: 'x' }.to_json,
             headers:)

        expect(response).to have_http_status(:bad_request)
      end
    end

    context 'when provider_type is missing' do
      it 'returns 400' do
        post('/vaos/v2/unified_bookings',
             params: { slot_id: 'x' }.to_json,
             headers:)

        expect(response).to have_http_status(:bad_request)
      end
    end

    context 'when user is not LOA3' do
      let(:current_user) { build(:user, :loa1) }

      it 'returns 403' do
        post('/vaos/v2/unified_bookings',
             params: { provider_type: 'va', slot_id: 'x' }.to_json,
             headers:)

        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
