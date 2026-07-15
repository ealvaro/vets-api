# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VAOS::V2::Unified::SlotsService do
  let(:user) { build(:user, :vaos) }
  let(:service) { described_class.new(user) }

  before { allow(StatsD).to receive(:increment) }

  describe '#slots_for' do
    context 'with an unsupported provider' do
      let(:provider) { VAOS::V2::Unified::BaseProvider.new(id: 'x') }

      it 'raises ArgumentError' do
        expect do
          service.slots_for(provider:, start_dt: '2025-01-01T00:00:00Z', end_dt: '2025-01-02T00:00:00Z')
        end.to raise_error(ArgumentError, /Unsupported provider type/)
      end
    end

    context 'with VAProvider' do
      let(:systems_service) { instance_double(VAOS::V2::SystemsService) }
      let(:start_dt) { '2025-01-01T00:00:00Z' }
      let(:end_dt) { '2025-01-02T00:00:00Z' }
      let(:raw_slot) do
        OpenStruct.new(
          id: 'slot-1',
          start: '2025-01-01T10:00:00Z',
          end: '2025-01-01T10:30:00Z',
          clinic: { clinic_ien: '1081' },
          location: { vha_facility_id: '983' }
        )
      end

      before do
        allow(VAOS::V2::SystemsService).to receive(:new).with(user).and_return(systems_service)
        allow(systems_service).to receive(:get_available_slots).and_return([raw_slot])
      end

      context 'at a VistA-backed VA health facility' do
        let(:provider) do
          VAOS::V2::Unified::VAProvider.new(
            id: '1081',
            location_id: '983',
            facility_type: 'va_health_facility'
          )
        end

        it 'returns normalized VASlot records' do
          slots = service.slots_for(
            provider:, start_dt:, end_dt:, clinical_service: 'audiology'
          )

          expect(slots.size).to eq(1)
          expect(slots.first).to be_a(VAOS::V2::Unified::VASlot)
          expect(slots.first.id).to eq('slot-1')
          expect(slots.first.location_id).to eq('983')
        end

        it 'does NOT forward clinical_service to SystemsService (VPG rejects it for VistA)' do
          service.slots_for(provider:, start_dt:, end_dt:, clinical_service: 'audiology')

          expect(systems_service).to have_received(:get_available_slots).with(
            hash_including(clinical_service: nil, location_id: '983', clinic_id: '1081')
          )
        end

        it 'succeeds when clinical_service is omitted entirely' do
          expect do
            service.slots_for(provider:, start_dt:, end_dt:)
          end.not_to raise_error
        end

        it 'returns an empty array when upstream returns no slots' do
          allow(systems_service).to receive(:get_available_slots).and_return([])

          slots = service.slots_for(provider:, start_dt:, end_dt:)
          expect(slots).to eq([])
        end

        it 'emits fetch success and no_results metrics for empty VA slot responses' do
          allow(systems_service).to receive(:get_available_slots).and_return([])

          service.slots_for(provider:, start_dt:, end_dt:)

          expect(StatsD).to have_received(:increment)
            .with('api.vaos.unified_slots.fetch.success', tags: ['provider_type:va'])
          expect(StatsD).to have_received(:increment)
            .with('api.vaos.unified_slots.fetch.no_results', tags: ['provider_type:va'])
        end
      end

      context 'at a Cerner / Oracle Health facility' do
        let(:provider) do
          VAOS::V2::Unified::VAProvider.new(
            id: '1081',
            location_id: '668',
            facility_type: 'va_cerner_facility'
          )
        end

        it 'forwards clinical_service to SystemsService' do
          service.slots_for(provider:, start_dt:, end_dt:, clinical_service: 'audiology')

          expect(systems_service).to have_received(:get_available_slots).with(
            hash_including(clinical_service: 'audiology', location_id: '668', clinic_id: '1081')
          )
        end

        it 'raises ParameterMissing when clinical_service is blank' do
          expect do
            service.slots_for(provider:, start_dt:, end_dt:, clinical_service: nil)
          end.to raise_error(Common::Exceptions::ParameterMissing)
        end

        it 'raises ParameterMissing when clinical_service is an empty string' do
          expect do
            service.slots_for(provider:, start_dt:, end_dt:, clinical_service: '')
          end.to raise_error(Common::Exceptions::ParameterMissing)
        end
      end

      context 'when provider id (clinic IEN) is blank' do
        let(:provider) do
          VAOS::V2::Unified::VAProvider.new(id: nil, location_id: '983', facility_type: 'va_health_facility')
        end

        it 'raises UnprocessableEntity regardless of facility type' do
          expect do
            service.slots_for(provider:, start_dt:, end_dt:, clinical_service: 'audiology')
          end.to raise_error(Common::Exceptions::UnprocessableEntity)
        end
      end
    end

    context 'with EpsProvider' do
      let(:appointment_types) do
        [
          { id: 'phone', is_self_schedulable: false },
          { id: 'ov', is_self_schedulable: true }
        ]
      end

      let(:provider) do
        VAOS::V2::Unified::EpsProvider.new(
          id: '9mN718pH',
          appointment_types:
        )
      end

      let(:eps_service) { instance_double(Eps::ProviderService) }
      # Far-future fixture date keeps the slot well outside any business-day
      # lead-time floor regardless of when this spec runs.
      let(:start_dt) { '2099-01-01T00:00:00Z' }
      let(:end_dt) { '2099-01-02T00:00:00Z' }
      let(:appointment_id) { 'draft-1' }

      before do
        allow(Eps::ProviderService).to receive(:new).with(user).and_return(eps_service)
      end

      it 'returns normalized EpsSlot records and passes EPS slot params' do
        allow(eps_service).to receive(:get_provider_slots).and_return(
          OpenStruct.new(slots: [{ id: 'eps-slot', start: '2099-01-01T12:00:00Z', provider_service_id: '9mN718pH' }])
        )

        slots = service.slots_for(
          provider:,
          start_dt:,
          end_dt:,
          appointment_id:
        )

        expect(slots.size).to eq(1)
        expect(slots.first).to be_a(VAOS::V2::Unified::EpsSlot)
        expect(slots.first.id).to eq('eps-slot')
        expect(eps_service).to have_received(:get_provider_slots).with(
          '9mN718pH',
          {
            appointmentTypeId: 'ov',
            startOnOrAfter: start_dt,
            startBefore: end_dt,
            appointmentId: appointment_id
          }
        )
      end

      it 'returns an empty array when EPS returns no slots key' do
        allow(eps_service).to receive(:get_provider_slots).and_return(OpenStruct.new(slots: nil))

        slots = service.slots_for(
          provider:,
          start_dt:,
          end_dt:,
          appointment_id:
        )

        expect(slots).to eq([])
      end

      it 'raises when appointment_types is blank' do
        provider.appointment_types = []

        expect do
          service.slots_for(provider:, start_dt:, end_dt:, appointment_id:)
        end.to raise_error(Common::Exceptions::BackendServiceException)
      end

      it 'raises when no self-schedulable appointment types exist' do
        provider.appointment_types = [{ id: 'phone', is_self_schedulable: false }]

        expect do
          service.slots_for(provider:, start_dt:, end_dt:, appointment_id:)
        end.to raise_error(Common::Exceptions::BackendServiceException)
      end

      it 'raises when appointment_id is blank' do
        expect do
          service.slots_for(
            provider:,
            start_dt:,
            end_dt:,
            appointment_id: nil
          )
        end.to raise_error(Common::Exceptions::ParameterMissing)
      end

      context 'with the CC 3-business-day lead-time filter' do
        let(:near_slot) { { id: 'near', start: '2026-05-13T12:00:00-04:00', provider_service_id: '9mN718pH' } } # Wed
        let(:far_slot)  { { id: 'far',  start: '2026-05-15T12:00:00-04:00', provider_service_id: '9mN718pH' } } # Fri

        it 'drops slots fewer than 3 business days out (Mon ref -> Thu cutoff)' do
          allow(eps_service).to receive(:get_provider_slots).and_return(
            OpenStruct.new(slots: [near_slot, far_slot])
          )

          Timecop.freeze(Time.zone.parse('2026-05-11T10:00:00-04:00')) do
            slots = service.slots_for(provider:, start_dt:, end_dt:, appointment_id:)
            expect(slots.map(&:id)).to eq(['far'])
          end
        end

        it 'emits a lead_time.filtered metric for dropped near-term EPS slots' do
          allow(eps_service).to receive(:get_provider_slots).and_return(
            OpenStruct.new(slots: [near_slot, far_slot])
          )

          Timecop.freeze(Time.zone.parse('2026-05-11T10:00:00-04:00')) do
            service.slots_for(provider:, start_dt:, end_dt:, appointment_id:)
          end

          expect(StatsD).to have_received(:increment)
            .with('api.vaos.unified_slots.lead_time.filtered', 1, tags: ['provider_type:eps'])
        end
      end
    end
  end
end
