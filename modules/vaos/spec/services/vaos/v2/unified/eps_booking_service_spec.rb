# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VAOS::V2::Unified::EpsBookingService do
  let(:user) { build(:user, :vaos) }
  let(:provider) do
    VAOS::V2::Unified::EpsProvider.new(
      id: 'ps-1',
      name: 'CC Provider',
      provider_service_id: 'provider-svc-99',
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
  let(:service) { described_class.new(appointment_service:) }

  before do
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:error)
    allow(StatsD).to receive(:increment)
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
      expect(appointment_service).to receive(:create_draft_appointment).with(referral_id: 'REF-12345')
                                                                       .and_return(draft_response)

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
        provider_type: 'community_care',
        status: 'booked',
        start: '2026-04-10T15:00:00Z'
      )
    end

    context 'when referral_id is used instead of referral_number' do
      let(:base_params) { { referral_id: 'VA0000001234' } }

      it 'passes the same value to draft and submit' do
        expect(appointment_service).to receive(:create_draft_appointment).with(referral_id: 'VA0000001234')
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
        VAOS::V2::Unified::EpsProvider.new(id: 'ps-1', name: 'X', provider_service_id: 'p1', network_id: nil)
      end

      it 'raises BookingArgumentError' do
        expect do
          service.book(user:, provider:, slot:, params: { referral_number: 'R1' })
        end.to raise_error(VAOS::V2::Unified::BookingArgumentError, /network_id/)
      end
    end

    context 'when provider_service_id cannot be resolved' do
      let(:provider) do
        VAOS::V2::Unified::EpsProvider.new(id: 'ps-1', name: 'X', provider_service_id: nil, network_id: 'net-1')
      end
      let(:slot) { VAOS::V2::Unified::EpsSlot.new(id: 'slot-1', start: '2026-04-10T15:00:00Z') }

      it 'raises BookingArgumentError' do
        expect do
          service.book(user:, provider:, slot:, params: { referral_number: 'R1' })
        end.to raise_error(VAOS::V2::Unified::BookingArgumentError, /provider_service_id/)
      end
    end

    context 'when draft response has no id' do
      let(:draft_response) { OpenStruct.new(state: 'draft') }

      it 'raises BackendServiceException' do
        expect do
          service.book(user:, provider:, slot:, params: base_params)
        end.to raise_error(VAOS::V2::Unified::BookingUpstreamContractError, /draft response missing/)
      end
    end

    context 'when submit response has no id' do
      let(:submit_response) { OpenStruct.new(state: 'booked') }

      it 'raises BackendServiceException' do
        expect do
          service.book(user:, provider:, slot:, params: base_params)
        end.to raise_error(VAOS::V2::Unified::BookingUpstreamContractError, /submit response missing/)
      end
    end

    context 'when create_draft_appointment raises' do
      before do
        allow(appointment_service).to receive(:create_draft_appointment)
          .and_raise(Common::Exceptions::BackendServiceException.new(nil, {}, 502))
      end

      it 'raises through and logs failure metrics' do
        expect do
          service.book(user:, provider:, slot:, params: base_params)
        end.to raise_error(Common::Exceptions::BackendServiceException)

        expect(StatsD).to have_received(:increment).with(
          'api.vaos.unified_booking.failure',
          tags: [
            'provider_type:community_care',
            'error_type:backend_service_exception'
          ]
        )
        expect(Rails.logger).to have_received(:error).with(
          'api.vaos.unified_booking: unified booking request failed',
          hash_including(error_class: 'Common::Exceptions::BackendServiceException', provider_type: 'community_care')
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
        allow(appointment_service).to receive(:create_draft_appointment).and_return(draft_response)
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
            'provider_type:community_care',
            'error_type:backend_service_exception'
          ]
        )
        expect(Rails.logger).to have_received(:error).with(
          'api.vaos.unified_booking: unified booking request failed',
          hash_including(error_class: 'Common::Exceptions::BackendServiceException', provider_type: 'community_care')
        )
      end
    end

    context 'when using default Eps::AppointmentService construction' do
      let(:service) { described_class.new }
      let(:real_service) { instance_double(Eps::AppointmentService) }

      before do
        allow(Eps::AppointmentService).to receive(:new).with(user).and_return(real_service)
        allow(real_service).to receive_messages(
          create_draft_appointment: draft_response,
          submit_appointment: submit_response
        )
      end

      it 'instantiates Eps::AppointmentService with the user from #book' do
        service.book(user:, provider:, slot:, params: base_params)

        expect(Eps::AppointmentService).to have_received(:new).with(user)
      end
    end
  end
end
