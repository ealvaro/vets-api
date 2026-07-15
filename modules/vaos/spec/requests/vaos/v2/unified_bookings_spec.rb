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

      it 'increments booking success tagged provider_type:va via the booking service' do
        post('/vaos/v2/unified_bookings', params: va_params.to_json, headers:)

        expect(StatsD).to have_received(:increment)
          .with('api.vaos.unified_booking.success', tags: ['provider_type:va'])
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

      context 'with slot_start supplied' do
        let(:slot_start) { '2026-04-15T14:00:00Z' }

        it 'forwards slot_start as desired_date in the VAOS request extension' do
          post('/vaos/v2/unified_bookings',
               params: va_params.merge(slot_start:, slot_end: '2026-04-15T14:30:00Z').to_json,
               headers:)

          expect(response).to have_http_status(:created)
          expect(mock_appointments_service).to have_received(:post_appointment).with(
            hash_including(extension: hash_including(:desired_date))
          )
        end
      end

      context 'without slot_start' do
        it 'omits the extension block (no desired_date) so VAOS does not get an empty hash' do
          post('/vaos/v2/unified_bookings', params: va_params.to_json, headers:)

          body_arg = nil
          expect(mock_appointments_service).to have_received(:post_appointment) { |b| body_arg = b }
          expect(body_arg).not_to have_key(:extension)
        end
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

        it 'increments booking failure tagged provider_type:va via the booking service' do
          post('/vaos/v2/unified_bookings', params: va_params.to_json, headers:)

          expect(StatsD).to have_received(:increment)
            .with(
              'api.vaos.unified_booking.failure',
              tags: ['provider_type:va', 'error_type:backend_service_exception']
            )
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
      let(:mock_eps_draft_service) { instance_double(VAOS::V2::Unified::EpsDraftService) }

      let(:mock_draft_response) { OpenStruct.new(id: 'draft-001', state: 'draft') }

      let(:mock_submit_response) do
        OpenStruct.new(id: 'draft-001', state: 'booked', start: '2026-04-15T10:00:00Z')
      end

      before do
        allow(Eps::AppointmentService).to receive(:new).and_return(mock_eps_service)
        allow(VAOS::V2::Unified::EpsDraftService).to receive(:new).and_return(mock_eps_draft_service)
        allow(mock_eps_draft_service).to receive(:create_for_referral).and_return('draft-001')
        allow(mock_eps_service).to receive(:submit_appointment).and_return(mock_submit_response)
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

      it 'increments booking success tagged provider_type:eps via the booking service' do
        post('/vaos/v2/unified_bookings', params: eps_params.to_json, headers:)

        expect(StatsD).to have_received(:increment)
          .with('api.vaos.unified_booking.success', tags: ['provider_type:eps'])
      end

      it 'calls the guarded draft service then submit_appointment' do
        post('/vaos/v2/unified_bookings', params: eps_params.to_json, headers:)

        expect(mock_eps_draft_service).to have_received(:create_for_referral) do |referral|
          expect(referral.referral_number).to eq('VA0000005678')
        end
        expect(mock_eps_service).to have_received(:submit_appointment)
          .with('draft-001', hash_including(
                               network_id: 'sandbox-net-1',
                               provider_service_id: 'prov-789',
                               referral_number: 'VA0000005678'
                             ))
      end

      # Regression tests for the +invalid appointmentId+ production bug, end-to-end.
      # The FE was populating +appointmentId+ in the booking body with the
      # +provider_service_id+ instead of the slots-time draft id; the controller
      # used to permit that field and forward it as the Wellhive draft id,
      # producing a +400 invalid appointmentId+ from Wellhive.
      #
      # The fix has two layers we want locked in here:
      #   1. Strong params drops the field from the request entirely (no longer
      #      in +create_booking_params.permit(...)+, so Rails' default
      #      +action_on_unpermitted_parameters: :log+ silently filters it out --
      #      no 4xx, no surfacing into the booking service).
      #   2. The booking service mints/reuses a draft from the referral_number
      #      regardless of any client-supplied draft id.
      #
      # If a future config change ever flips +action_on_unpermitted_parameters+
      # to +:raise+ in any environment, these tests will fail loudly instead of
      # the bug silently coming back. We test BOTH the snake_case form (which
      # is what the controller actually sees in production -- after the
      # OliveBranch middleware normalizes the body) AND the raw camelCase form
      # (which is what the FE literally sends, in case the OliveBranch transform
      # is ever bypassed).
      it 'silently drops a snake_case appointment_id (post-OliveBranch shape) and mints/reuses the draft itself' do
        params_with_bogus_draft = eps_params.merge(appointment_id: 'prov-789')

        post('/vaos/v2/unified_bookings', params: params_with_bogus_draft.to_json, headers:)

        expect(response).to have_http_status(:created)
        expect(mock_eps_draft_service).to have_received(:create_for_referral) do |referral|
          expect(referral.referral_number).to eq('VA0000005678')
        end
        expect(mock_eps_service).to have_received(:submit_appointment)
          .with('draft-001', anything) # NOT 'prov-789'
      end

      it 'silently drops a camelCase appointmentId (raw FE shape) and mints/reuses the draft itself' do
        params_with_bogus_draft = eps_params.merge(appointmentId: 'prov-789')

        post('/vaos/v2/unified_bookings', params: params_with_bogus_draft.to_json, headers:)

        expect(response).to have_http_status(:created)
        expect(mock_eps_draft_service).to have_received(:create_for_referral) do |referral|
          expect(referral.referral_number).to eq('VA0000005678')
        end
        expect(mock_eps_service).to have_received(:submit_appointment)
          .with('draft-001', anything) # NOT 'prov-789'
      end

      context 'when EPS submit response has no start time and slot_start was supplied' do
        # The appointments list filters out EPS appointments missing a start time. With slot_start
        # in the request, the booking service falls back to it so the confirmation (and the FE-
        # facing list) still has a usable start.
        let(:slot_start) { '2026-04-15T10:00:00Z' }
        let(:mock_submit_response) { OpenStruct.new(id: 'draft-001', state: 'booked') }

        it 'returns slot_start as the confirmation start' do
          post('/vaos/v2/unified_bookings',
               params: eps_params.merge(slot_start:).to_json,
               headers:)

          expect(response).to have_http_status(:created)
          body = JSON.parse(response.body)
          expect(body['data']['attributes']['start']).to eq(slot_start)
        end
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

      # BookingArgumentError is raised inside EpsBookingService (via BaseBookingService#book),
      # which emits api.vaos.unified_booking.failure before re-raising. The controller then
      # remaps it to ParameterMissing for the HTTP response without a second StatsD increment.
      it 'increments booking failure via the service when BookingArgumentError is remapped to 400' do
        post('/vaos/v2/unified_bookings',
             params: eps_params.except(:referral_number).to_json,
             headers:)

        expect(response).to have_http_status(:bad_request)
        expect(StatsD).to have_received(:increment)
          .with(
            'api.vaos.unified_booking.failure',
            tags: ['provider_type:eps', 'error_type:booking_argument_error']
          )
      end

      it 'returns 400 when network_id is missing' do
        post('/vaos/v2/unified_bookings',
             params: eps_params.except(:network_id).to_json,
             headers:)

        expect(response).to have_http_status(:bad_request)
      end

      context 'when EPS draft creation fails' do
        before do
          allow(mock_eps_draft_service).to receive(:create_for_referral)
            .and_raise(Common::Exceptions::BackendServiceException.new('VAOS_502'))
        end

        it 'returns a 502 error response' do
          post('/vaos/v2/unified_bookings', params: eps_params.to_json, headers:)

          expect(response).to have_http_status(:bad_gateway)
          body = JSON.parse(response.body)
          expect(body['errors']).to be_present
        end

        it 'increments booking failure tagged provider_type:eps via the booking service' do
          post('/vaos/v2/unified_bookings', params: eps_params.to_json, headers:)

          expect(StatsD).to have_received(:increment)
            .with(
              'api.vaos.unified_booking.failure',
              tags: ['provider_type:eps', 'error_type:backend_service_exception']
            )
        end
      end

      context 'when EPS draft response has no appointment id' do
        before do
          allow(mock_eps_draft_service).to receive(:create_for_referral)
            .and_raise(VAOS::V2::Unified::BookingUpstreamContractError, 'EPS draft response missing appointment id')
        end

        it 'returns 502' do
          post('/vaos/v2/unified_bookings', params: eps_params.to_json, headers:)

          expect(response).to have_http_status(:bad_gateway)
          body = JSON.parse(response.body)
          expect(body['errors']).to be_present
        end
      end

      context 'when EPS submit response has no appointment id' do
        # Wellhive's published Swagger does not guarantee +id+ on the submit response. Submit
        # operates on the draft id in the URL, so vets-api uses the draft id as the canonical
        # appointment id instead of failing the booking and stranding the user with a created
        # appointment they can no longer look up.
        before do
          allow(mock_eps_service).to receive(:submit_appointment)
            .and_return(OpenStruct.new(state: 'booked'))
        end

        it 'returns 201 with the draft id as the confirmation appointment id' do
          post('/vaos/v2/unified_bookings', params: eps_params.to_json, headers:)

          expect(response).to have_http_status(:created)
          body = JSON.parse(response.body)
          expect(body['data']['id']).to eq('draft-001')
          expect(body['data']['attributes']['appointment_id']).to eq('draft-001')
        end
      end

      context 'when EPS submit response returns a different id than the draft' do
        # Defensive: even if Wellhive does include +id+ on submit, we ignore it. The canonical
        # appointment resource is identified by the draft id we POSTed to.
        let(:mock_submit_response) do
          OpenStruct.new(id: 'eps-other-id-999', state: 'booked', start: '2026-04-15T10:00:00Z')
        end

        it 'uses the draft id, not the submit response id' do
          post('/vaos/v2/unified_bookings', params: eps_params.to_json, headers:)

          expect(response).to have_http_status(:created)
          body = JSON.parse(response.body)
          expect(body['data']['id']).to eq('draft-001')
          expect(body['data']['attributes']['appointment_id']).to eq('draft-001')
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

    context 'pilot station allowlist' do
      let(:va_params) do
        { provider_type: 'va', slot_id: 'slot-1', location_id: '983',
          clinic_id: '455', service_type: 'primaryCare' }
      end

      let(:mock_appointments_service) { instance_double(VAOS::V2::AppointmentsService) }

      before do
        allow(VAOS::V2::AppointmentsService).to receive(:new).and_return(mock_appointments_service)
        allow(mock_appointments_service).to receive(:post_appointment).and_return(
          OpenStruct.new(id: 'va-appt-001', status: 'booked', start: '2026-04-15T14:00:00Z')
        )
      end

      def stub_allowlist(value)
        allow(Settings.vaos.unified_scheduling)
          .to receive(:allowed_parent_stations).and_return(value)
      end

      it 'returns 404 for a VA booking against a non-allowlisted parent station' do
        stub_allowlist('442')

        post('/vaos/v2/unified_bookings', params: va_params.to_json, headers:)

        expect(response).to have_http_status(:not_found)
        expect(mock_appointments_service).not_to have_received(:post_appointment)
      end

      it 'allows a VA booking against an allowlisted parent station' do
        stub_allowlist('983')

        post('/vaos/v2/unified_bookings', params: va_params.to_json, headers:)

        expect(response).to have_http_status(:created)
      end

      it 'allows a VA booking against a satellite that rolls up to the parent' do
        stub_allowlist('983')

        post('/vaos/v2/unified_bookings',
             params: va_params.merge(location_id: '983GC').to_json, headers:)

        expect(response).to have_http_status(:created)
      end

      it 'allows any station when the allowlist is unset (default)' do
        stub_allowlist(nil)

        post('/vaos/v2/unified_bookings',
             params: va_params.merge(location_id: '552').to_json, headers:)

        expect(response).to have_http_status(:created)
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
