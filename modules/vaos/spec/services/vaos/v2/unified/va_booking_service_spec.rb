# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VAOS::V2::Unified::VABookingService do
  let(:user) { build(:user, :vaos) }
  let(:provider) do
    VAOS::V2::Unified::VAProvider.new(
      id: '455',
      name: 'Test VA',
      location_id: '983',
      service_type: 'primaryCare'
    )
  end
  let(:slot) do
    VAOS::V2::Unified::VASlot.from_vaos_slot(
      {
        id: '3230323231313330323034353A323032323131333032313030',
        start: '2022-11-30T20:45:00Z',
        end: '2022-11-30T21:15:00Z',
        location: { vha_facility_id: '983' },
        clinic: { clinic_ien: '999', name: 'AUDIOLOGY' }
      }
    )
  end
  let(:base_params) { {} }
  let(:appointments_service) { instance_double(VAOS::V2::AppointmentsService) }
  let(:service) { described_class.new }

  before do
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:error)
    allow(StatsD).to receive(:increment)
    allow(VAOS::V2::AppointmentsService).to receive(:new).with(user).and_return(appointments_service)
  end

  describe '#book' do
    let(:created_appointment) do
      {
        id: 'appt-123',
        status: 'booked',
        start: '2022-11-30T20:45:00Z'
      }
    end

    before do
      allow(appointments_service).to receive(:post_appointment).and_return(OpenStruct.new(created_appointment))
    end

    it 'calls post_appointment with clinic direct-scheduling fields' do
      expect(appointments_service).to receive(:post_appointment) do |body|
        expect(body[:kind]).to eq('clinic')
        expect(body[:status]).to eq('booked')
        expect(body[:location_id]).to eq('983')
        expect(body[:clinic]).to eq('455')
        expect(body[:slot]).to eq(id: '3230323231313330323034353A323032323131333032313030')
        expect(body[:reason_code]).to eq(described_class::PILOT_REASON_CODE)
        expect(body[:system_type]).to eq('vista')
        expect(body[:service_type]).to eq('primaryCare')
        expect(body[:extension]).to include(:desired_date)
        OpenStruct.new(created_appointment)
      end

      service.book(user:, provider:, slot:, params: base_params)
    end

    it 'returns a normalized confirmation' do
      result = service.book(user:, provider:, slot:, params: base_params)

      expect(result).to include(
        appointment_id: 'appt-123',
        provider_type: 'va',
        status: 'booked',
        start: '2022-11-30T20:45:00Z'
      )
    end

    context 'when extension is provided in params' do
      let(:extension) { { desired_date: DateTime.new(2022, 11, 30) } }

      it 'does not synthesize extension from the slot' do
        expect(appointments_service).to receive(:post_appointment).with(
          hash_including(extension:)
        ).and_return(OpenStruct.new(created_appointment))

        service.book(user:, provider:, slot:, params: base_params.merge(extension:))
      end
    end

    context 'when comment is present' do
      it 'includes comment on the request' do
        expect(appointments_service).to receive(:post_appointment).with(
          hash_including(comment: 'Need wheelchair access')
        ).and_return(OpenStruct.new(created_appointment))

        service.book(user:, provider:, slot:, params: base_params.merge(comment: 'Need wheelchair access'))
      end
    end

    context 'when the provider is not a VAProvider' do
      let(:provider) { VAOS::V2::Unified::EpsProvider.new(id: 'x', name: 'CC', provider_service_id: '1', network_id: 'n') }

      it 'raises ArgumentError before calling post_appointment' do
        expect(appointments_service).not_to receive(:post_appointment)

        expect do
          service.book(user:, provider:, slot:, params: base_params)
        end.to raise_error(ArgumentError, /VAProvider/)
      end
    end

    context 'when slot id is missing' do
      let(:slot) { VAOS::V2::Unified::VASlot.new(id: nil, start: '2022-11-30T20:45:00Z') }

      it 'raises ArgumentError' do
        expect do
          service.book(user:, provider:, slot:, params: base_params)
        end.to raise_error(ArgumentError, /slot id/)
      end
    end

    context 'when provider location_id is missing' do
      let(:provider) do
        VAOS::V2::Unified::VAProvider.new(id: '455', name: 'Test VA', location_id: nil, service_type: 'primaryCare')
      end

      it 'raises ArgumentError' do
        expect do
          service.book(user:, provider:, slot:, params: base_params)
        end.to raise_error(ArgumentError, /location_id/)
      end
    end

    context 'when provider service_type is missing' do
      let(:provider) do
        VAOS::V2::Unified::VAProvider.new(id: '455', name: 'Test VA', location_id: '983', service_type: nil)
      end

      it 'raises ArgumentError' do
        expect do
          service.book(user:, provider:, slot:, params: base_params)
        end.to raise_error(ArgumentError, /service_type/)
      end
    end

    context 'when post_appointment returns no id' do
      before do
        allow(appointments_service).to receive(:post_appointment).and_return(OpenStruct.new(status: 'booked'))
      end

      it 'raises ArgumentError' do
        expect do
          service.book(user:, provider:, slot:, params: base_params)
        end.to raise_error(ArgumentError, /missing appointment id/)
      end
    end

    context 'when post_appointment raises' do
      before do
        allow(appointments_service).to receive(:post_appointment)
          .and_raise(Common::Exceptions::BackendServiceException.new('VA900', {}, 502, 'upstream error'))
      end

      it 'logs failure metrics and re-raises' do
        expect { service.book(user:, provider:, slot:, params: base_params) }
          .to raise_error(Common::Exceptions::BackendServiceException)

        expect(StatsD).to have_received(:increment).with(
          "#{described_class::STATSD_KEY_PREFIX}.failure",
          tags: %w[provider_type:va error_type:backend_service_exception]
        )
      end
    end
  end
end
