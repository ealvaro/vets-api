# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VAOS::V2::Unified::EpsBookingService do
  let(:user) { build(:user, :vaos) }
  let(:provider) do
    VAOS::V2::Unified::EpsProvider.new(
      id: 'provider-svc-99',
      name: 'CC Provider',
      network_id: 'network-88'
    )
  end
  let(:slot) do
    VAOS::V2::Unified::EpsSlot.new(
      id: 'slot-composite-1',
      start: '2026-04-10T15:00:00Z',
      provider_service_id: 'provider-svc-99'
    )
  end
  let(:base_params) do
    { referral_number: 'REF-12345' }
  end
  let(:appointment_service) { instance_double(Eps::AppointmentService) }
  let(:redis_client) { instance_double(Eps::RedisClient) }
  let(:eps_draft_service) { instance_double(VAOS::V2::Unified::EpsDraftService) }
  let(:service) { described_class.new(appointment_service:, redis_client:, eps_draft_service:) }

  before do
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:error)
    allow(StatsD).to receive(:increment)

    # Default to "no cached draft" so legacy tests exercise the create-fresh path
    # without each one having to opt in. Tests that exercise the cache-hit path
    # override this to return a stored draft id.
    allow(redis_client).to receive_messages(
      fetch_draft_appointment_id: nil,
      delete_draft_appointment_id: true
    )
    allow(eps_draft_service).to receive(:create_for_referral).and_return('eps-draft-1')
  end

  describe '#book' do
    let(:draft_response) { OpenStruct.new(id: 'eps-draft-1', state: 'draft') }
    let(:submit_response) do
      OpenStruct.new(id: 'eps-draft-1', state: 'booked', start: '2026-04-10T15:00:00Z')
    end

    before do
      allow(appointment_service).to receive_messages(
        create_draft_appointment: draft_response,
        submit_appointment: submit_response
      )
    end

    it 'creates a draft with the referral id then submits with mapped EPS fields' do
      expect(eps_draft_service).to receive(:create_for_referral) do |referral|
        expect(referral.referral_number).to eq('REF-12345')
      end.and_return('eps-draft-1')

      expect(appointment_service).to receive(:submit_appointment).with(
        'eps-draft-1',
        {
          network_id: 'network-88',
          provider_service_id: 'provider-svc-99',
          slot_ids: ['slot-composite-1'],
          referral_number: 'REF-12345'
        }
      ).and_return(submit_response)

      service.book(user:, provider:, slot:, params: base_params)
    end

    it 'returns a normalized confirmation' do
      result = service.book(user:, provider:, slot:, params: base_params)

      expect(result).to include(
        appointment_id: 'eps-draft-1',
        provider_type: 'eps',
        status: 'booked',
        start: '2026-04-10T15:00:00Z'
      )
    end

    context 'when the client supplies an appointment_id' do
      # Defends against the FE bug where +appointment_id+ was being populated with
      # +provider_service_id+ (both are short opaque ids), which Wellhive rejected
      # at +POST /appointments/{appointment_id}/submit+ with +400 invalid appointmentId+.
      # The booking service must ignore client-supplied draft ids at every layer.
      let(:params_with_draft) { base_params.merge(appointment_id: 'provider-svc-99') }

      it 'ignores the client value and mints a fresh draft through the guarded draft service' do
        expect(eps_draft_service).to receive(:create_for_referral) do |referral|
          expect(referral.referral_number).to eq('REF-12345')
        end.and_return('eps-draft-1')
        expect(appointment_service).to receive(:submit_appointment).with(
          'eps-draft-1',
          hash_including(referral_number: 'REF-12345')
        ).and_return(submit_response)

        service.book(user:, provider:, slot:, params: params_with_draft)
      end
    end

    context 'when a draft id is cached for this (user, referral_number)' do
      # The slots controller mints a draft to satisfy Wellhive's slots-endpoint
      # +appointmentId+ query param and stashes that id in Redis. The booking
      # service must reuse it instead of minting a second draft.
      before do
        allow(redis_client).to receive(:fetch_draft_appointment_id)
          .with(uuid: user.uuid, referral_number: 'REF-12345')
          .and_return('cached-draft-7')
      end

      it 'reuses the cached draft id and skips create_draft_appointment' do
        expect(appointment_service).not_to receive(:create_draft_appointment)
        expect(appointment_service).to receive(:submit_appointment).with(
          'cached-draft-7',
          hash_including(referral_number: 'REF-12345')
        ).and_return(submit_response)

        service.book(user:, provider:, slot:, params: base_params)
      end

      it 'invalidates the cached draft id after a successful submit' do
        expect(appointment_service).to receive(:submit_appointment)
          .with('cached-draft-7', anything)
          .and_return(submit_response)
        expect(redis_client).to receive(:delete_draft_appointment_id)
          .with(uuid: user.uuid, referral_number: 'REF-12345')

        service.book(user:, provider:, slot:, params: base_params)
      end

      # Models the abandon-and-pick-a-different-slot UX: user opens slots,
      # gets a list, picks slot S1, goes to confirmation, navigates back,
      # picks slot S2 from the same already-loaded list (no re-fetch of
      # +/provider_slots+), then submits. The cache still holds the original
      # draft from the initial slots fetch; the FE-supplied slot id is the
      # new pick. Wellhive accepts (cached draft, new slot) because slot ids
      # are (network, provider, time, appointment-type)-scoped, not
      # draft-scoped -- if Wellhive ever changes that contract, this test
      # is what surfaces it.
      context 'and the user picks a different slot from a stale list (no slots re-fetch)' do
        let(:different_slot) do
          VAOS::V2::Unified::EpsSlot.new(
            id: 'slot-composite-2-different-time',
            start: '2026-04-11T15:00:00Z',
            provider_service_id: 'provider-svc-99'
          )
        end

        it 'submits the cached draft with the newly-picked slot id' do
          expect(appointment_service).not_to receive(:create_draft_appointment)
          expect(appointment_service).to receive(:submit_appointment).with(
            'cached-draft-7',
            hash_including(slot_ids: ['slot-composite-2-different-time'])
          ).and_return(submit_response)

          service.book(user:, provider:, slot: different_slot, params: base_params)
        end
      end
    end

    context 'when no draft id is cached (normal cache miss)' do
      it 'runs the guarded draft service and uses that id for submit' do
        expect(redis_client).to receive(:fetch_draft_appointment_id)
          .with(uuid: user.uuid, referral_number: 'REF-12345')
          .and_return(nil)
        expect(eps_draft_service).to receive(:create_for_referral) do |referral|
          expect(referral.referral_number).to eq('REF-12345')
        end.and_return('eps-draft-1')
        expect(appointment_service).to receive(:submit_appointment)
          .with('eps-draft-1', anything)
          .and_return(submit_response)

        service.book(user:, provider:, slot:, params: base_params)
      end

      # Guards the cache-miss fallback: even when the slots-created draft has
      # expired from Redis (or the client skipped the slots step), we must not
      # mint a raw Wellhive draft directly. The fallback has to re-run
      # +EpsDraftService+ so the legacy "referral already used" precheck still
      # executes before any new draft is created.
      it 'does not call Eps::AppointmentService#create_draft_appointment directly' do
        expect(appointment_service).not_to receive(:create_draft_appointment)

        service.book(user:, provider:, slot:, params: base_params)
      end
    end

    context 'when submit fails after a cache hit' do
      before do
        allow(redis_client).to receive(:fetch_draft_appointment_id).and_return('cached-draft-7')
        allow(appointment_service).to receive(:submit_appointment)
          .and_raise(Common::Exceptions::BackendServiceException.new(nil, {}, 500))
      end

      # On submit failure we leave the cached draft alone so a legitimate retry
      # can reuse it; deleting unconditionally would force a second draft creation
      # for every transient Wellhive blip.
      it 'does NOT invalidate the cached draft id' do
        expect(redis_client).not_to receive(:delete_draft_appointment_id)

        expect do
          service.book(user:, provider:, slot:, params: base_params)
        end.to raise_error(Common::Exceptions::BackendServiceException)
      end
    end

    context 'when referral_id is used instead of referral_number' do
      let(:base_params) { { referral_id: 'VA0000001234' } }

      it 'passes the same value to draft and submit' do
        expect(eps_draft_service).to receive(:create_for_referral) do |referral|
          expect(referral.referral_number).to eq('VA0000001234')
        end.and_return('eps-draft-1')
        expect(appointment_service).to receive(:submit_appointment).with(
          'eps-draft-1',
          hash_including(referral_number: 'VA0000001234')
        ).and_return(submit_response)

        service.book(user:, provider:, slot:, params: base_params)
      end
    end

    context 'when params override provider network and provider_service_id' do
      let(:base_params) do
        super().merge(network_id: 'net-override', provider_service_id: 'prov-override', slot_id: 'slot-xyz')
      end

      it 'prefers explicit params' do
        expect(appointment_service).to receive(:submit_appointment).with(
          'eps-draft-1',
          hash_including(
            network_id: 'net-override',
            provider_service_id: 'prov-override',
            slot_ids: ['slot-xyz']
          )
        ).and_return(submit_response)

        service.book(user:, provider:, slot:, params: base_params)
      end
    end

    context 'when additional_patient_attributes is present' do
      let(:attrs) { { name: { given: ['Jane'], family: 'Doe' } } }
      let(:base_params) { super().merge(additional_patient_attributes: attrs) }

      it 'includes them on submit' do
        expect(appointment_service).to receive(:submit_appointment).with(
          'eps-draft-1',
          hash_including(additional_patient_attributes: attrs)
        ).and_return(submit_response)

        service.book(user:, provider:, slot:, params: base_params)
      end
    end

    context 'when the provider is not an EpsProvider' do
      let(:provider) { VAOS::V2::Unified::VAProvider.new(id: 'vha_1', name: 'VA', location_id: '983') }

      it 'raises before calling EPS' do
        expect(appointment_service).not_to receive(:create_draft_appointment)

        expect do
          service.book(user:, provider:, slot:, params: base_params)
        end.to raise_error(VAOS::V2::Unified::BookingArgumentError, /EpsProvider/)
      end
    end

    context 'when referral is missing' do
      it 'raises BookingArgumentError' do
        expect do
          service.book(user:, provider:, slot:, params: {})
        end.to raise_error(VAOS::V2::Unified::BookingArgumentError, /referral/)
      end
    end

    context 'when slot is nil' do
      let(:slot) { nil }

      it 'raises BookingArgumentError before calling EPS' do
        expect(appointment_service).not_to receive(:create_draft_appointment)

        expect do
          service.book(user:, provider:, slot:, params: base_params)
        end.to raise_error(VAOS::V2::Unified::BookingArgumentError, /slot is required/)
      end
    end

    context 'when slot id is missing' do
      let(:slot) { VAOS::V2::Unified::EpsSlot.new(id: nil, start: '2026-04-10T15:00:00Z') }

      it 'raises BookingArgumentError' do
        expect do
          service.book(user:, provider:, slot:, params: base_params)
        end.to raise_error(VAOS::V2::Unified::BookingArgumentError, /slot id/)
      end
    end

    context 'when network_id cannot be resolved' do
      let(:provider) do
        VAOS::V2::Unified::EpsProvider.new(id: 'p1', name: 'X', network_id: nil)
      end

      it 'raises BookingArgumentError' do
        expect do
          service.book(user:, provider:, slot:, params: { referral_number: 'R1' })
        end.to raise_error(VAOS::V2::Unified::BookingArgumentError, /network_id/)
      end
    end

    context 'when provider_service_id cannot be resolved' do
      let(:provider) do
        VAOS::V2::Unified::EpsProvider.new(id: nil, name: 'X', network_id: 'net-1')
      end
      let(:slot) { VAOS::V2::Unified::EpsSlot.new(id: 'slot-1', start: '2026-04-10T15:00:00Z') }

      it 'raises BookingArgumentError' do
        expect do
          service.book(user:, provider:, slot:, params: { referral_number: 'R1' })
        end.to raise_error(VAOS::V2::Unified::BookingArgumentError, /provider_service_id/)
      end
    end

    context 'when guarded draft service reports a missing draft id' do
      before do
        allow(eps_draft_service).to receive(:create_for_referral)
          .and_raise(VAOS::V2::Unified::BookingUpstreamContractError, 'EPS draft response missing appointment id')
      end

      it 'raises BackendServiceException' do
        expect do
          service.book(user:, provider:, slot:, params: base_params)
        end.to raise_error(VAOS::V2::Unified::BookingUpstreamContractError, /draft response missing/)
      end
    end

    context 'when submit response has no id' do
      # Wellhive's published Swagger does not guarantee +id+ on submit. The appointment lives at
      # the draft id we just submitted to (POST .../appointments/{draft_id}/submit), so the
      # confirmation always uses the draft id regardless of whether the submit body echoes it.
      let(:submit_response) { OpenStruct.new(state: 'booked') }

      it 'still returns the draft id as the confirmation appointment id' do
        result = service.book(user:, provider:, slot:, params: base_params)

        expect(result[:appointment_id]).to eq('eps-draft-1')
      end
    end

    context 'when submit response returns a different id than the draft' do
      # Defensive: even if Wellhive does include +id+ on submit, we ignore it because the
      # canonical EPS appointment resource is identified by the draft id we POSTed to.
      let(:submit_response) do
        OpenStruct.new(id: 'eps-other-id-999', state: 'booked', start: '2026-04-10T15:00:00Z')
      end

      it 'uses the draft id, not the submit response id' do
        result = service.book(user:, provider:, slot:, params: base_params)

        expect(result[:appointment_id]).to eq('eps-draft-1')
      end
    end

    context 'when the guarded draft service raises' do
      before do
        allow(eps_draft_service).to receive(:create_for_referral)
          .and_raise(Common::Exceptions::BackendServiceException.new(nil, {}, 502))
      end

      it 'raises through and logs failure metrics' do
        expect do
          service.book(user:, provider:, slot:, params: base_params)
        end.to raise_error(Common::Exceptions::BackendServiceException)

        expect(StatsD).to have_received(:increment).with(
          'api.vaos.unified_booking.failure',
          tags: [
            'provider_type:eps',
            'error_type:backend_service_exception'
          ]
        )
        expect(Rails.logger).to have_received(:error).with(
          'api.vaos.unified_booking: unified booking request failed',
          hash_including(error_class: 'Common::Exceptions::BackendServiceException', provider_type: 'eps')
        )
      end

      it 'does not call submit_appointment' do
        expect(appointment_service).not_to receive(:submit_appointment)

        expect do
          service.book(user:, provider:, slot:, params: base_params)
        end.to raise_error(Common::Exceptions::BackendServiceException)
      end
    end

    context 'when submit_appointment raises' do
      before do
        allow(eps_draft_service).to receive(:create_for_referral).and_return('eps-draft-1')
        allow(appointment_service).to receive(:submit_appointment)
          .and_raise(Common::Exceptions::BackendServiceException.new(nil, {}, 500))
      end

      it 'raises through and logs failure metrics' do
        expect do
          service.book(user:, provider:, slot:, params: base_params)
        end.to raise_error(Common::Exceptions::BackendServiceException)

        expect(StatsD).to have_received(:increment).with(
          'api.vaos.unified_booking.failure',
          tags: [
            'provider_type:eps',
            'error_type:backend_service_exception'
          ]
        )
        expect(Rails.logger).to have_received(:error).with(
          'api.vaos.unified_booking: unified booking request failed',
          hash_including(error_class: 'Common::Exceptions::BackendServiceException', provider_type: 'eps')
        )
      end
    end

    context 'when using default service construction' do
      let(:service) { described_class.new }
      let(:real_service) { instance_double(Eps::AppointmentService) }
      let(:real_draft_service) { instance_double(VAOS::V2::Unified::EpsDraftService) }

      before do
        allow(Eps::AppointmentService).to receive(:new).with(user).and_return(real_service)
        allow(VAOS::V2::Unified::EpsDraftService).to receive(:new).with(user).and_return(real_draft_service)
        allow(real_draft_service).to receive(:create_for_referral).and_return('eps-draft-1')
        allow(real_service).to receive(:submit_appointment).and_return(submit_response)
      end

      it 'instantiates Eps::AppointmentService and EpsDraftService with the user from #book' do
        service.book(user:, provider:, slot:, params: base_params)

        expect(Eps::AppointmentService).to have_received(:new).with(user)
        expect(VAOS::V2::Unified::EpsDraftService).to have_received(:new).with(user)
      end
    end
  end
end
