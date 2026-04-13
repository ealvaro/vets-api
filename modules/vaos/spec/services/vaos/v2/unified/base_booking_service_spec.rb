# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VAOS::V2::Unified::BaseBookingService do
  let(:user) { build(:user, :vaos) }
  let(:provider) { instance_double(VAOS::V2::Unified::BaseProvider, provider_type: 'va') }
  let(:slot) { instance_double(VAOS::V2::Unified::BaseSlot) }
  let(:params) { {} }

  describe '#book' do
    it 'raises NotImplementedError when perform_booking is not implemented' do
      expect { described_class.new.book(user:, provider:, slot:, params:) }
        .to raise_error(NotImplementedError, /must implement #perform_booking/)
    end
  end

  describe '.confirmation_shape' do
    it 'documents required and optional confirmation keys' do
      shape = described_class.confirmation_shape

      expect(shape[:required]).to eq(%i[appointment_id provider_type status])
      expect(shape[:optional]).to eq(described_class::OPTIONAL_CONFIRMATION_KEYS)
      expect(shape[:description]).to be_present
    end
  end

  describe 'booking through a concrete subclass' do
    let(:concrete_class) do
      Class.new(described_class) do
        attr_writer :force_result, :force_error

        private

        def perform_booking(**kwargs)
          raise @force_error if @force_error
          return @force_result if instance_variable_defined?(:@force_result)

          build_booking_confirmation(
            appointment_id: kwargs.dig(:params, :id) || 'appt-1',
            provider_type: kwargs[:provider].provider_type,
            status: 'booked',
            start: kwargs.dig(:params, :start)
          )
        end
      end
    end

    let(:service) { concrete_class.new }

    before do
      allow(Rails.logger).to receive(:info)
      allow(Rails.logger).to receive(:error)
      allow(StatsD).to receive(:increment)
    end

    context 'when booking succeeds' do
      it 'returns a validated confirmation hash' do
        result = service.book(user:, provider:, slot:, params: { id: 'va-99' })

        expect(result).to eq(appointment_id: 'va-99', provider_type: 'va', status: 'booked')
      end

      it 'includes start when provided' do
        result = service.book(user:, provider:, slot:, params: { start: '2026-04-10T14:00:00Z' })

        expect(result[:start]).to eq('2026-04-10T14:00:00Z')
      end

      it 'accepts string keys in the confirmation hash' do
        service.force_result = { 'appointment_id' => '1', 'provider_type' => 'va', 'status' => 'booked' }

        result = service.book(user:, provider:, slot:, params:)

        expect(result[:appointment_id]).to eq('1')
      end

      it 'logs success metrics' do
        service.book(user:, provider:, slot:, params: { id: 'va-99' })

        expect(Rails.logger).to have_received(:info).with(
          "#{described_class::STATSD_KEY_PREFIX}.success",
          { provider_type: 'va' }
        )
        expect(StatsD).to have_received(:increment).with(
          "#{described_class::STATSD_KEY_PREFIX}.success",
          tags: ['provider_type:va']
        )
      end
    end

    context 'when perform_booking raises' do
      before { service.force_error = StandardError.new('upstream timeout') }

      it 'logs failure metrics and re-raises' do
        expect { service.book(user:, provider:, slot:, params:) }
          .to raise_error(StandardError, 'upstream timeout')

        expect(Rails.logger).to have_received(:error).with(
          described_class::FAILURE_LOG_MESSAGE,
          { error_class: 'StandardError', provider_type: 'va' }
        )
        expect(StatsD).to have_received(:increment).with(
          "#{described_class::STATSD_KEY_PREFIX}.failure",
          tags: %w[provider_type:va error_type:standard_error]
        )
      end

      it 'does not include error.message in the log payload' do
        service.force_error = StandardError.new('contains sensitive PII data')

        expect { service.book(user:, provider:, slot:, params:) }
          .to raise_error(StandardError)

        expect(Rails.logger).to have_received(:error).with(
          described_class::FAILURE_LOG_MESSAGE,
          { error_class: 'StandardError', provider_type: 'va' }
        )
      end
    end

    context 'when validation fails' do
      it 'raises when confirmation is missing required keys' do
        service.force_result = { appointment_id: '1' }

        expect { service.book(user:, provider:, slot:, params:) }
          .to raise_error(VAOS::V2::Unified::BookingUpstreamContractError, /missing keys/)

        expect(Rails.logger).to have_received(:error).with(
          "#{described_class::STATSD_KEY_PREFIX}.argument_error",
          { reason: 'invalid_confirmation', missing_keys: %w[provider_type status] }
        )
        expect(StatsD).to have_received(:increment).with(
          "#{described_class::STATSD_KEY_PREFIX}.argument_error",
          tags: ['reason:invalid_confirmation']
        )
      end

      it 'raises when a required value is blank' do
        service.force_result = { appointment_id: '1', provider_type: '', status: 'booked' }

        expect { service.book(user:, provider:, slot:, params:) }
          .to raise_error(VAOS::V2::Unified::BookingUpstreamContractError, /blank required values/)
      end

      it 'raises when confirmation is not a Hash' do
        service.force_result = nil

        expect { service.book(user:, provider:, slot:, params:) }
          .to raise_error(VAOS::V2::Unified::BookingUpstreamContractError, /must be a Hash/)
      end

      it 'also logs a booking failure for validation errors' do
        service.force_result = { appointment_id: '1' }

        expect { service.book(user:, provider:, slot:, params:) }
          .to raise_error(VAOS::V2::Unified::BookingUpstreamContractError)

        expect(StatsD).to have_received(:increment).with(
          "#{described_class::STATSD_KEY_PREFIX}.failure",
          tags: %w[provider_type:va error_type:booking_upstream_contract_error]
        )
      end
    end

    context 'when an error is logged by the service' do
      it 'tags the error with AlreadyLogged' do
        service.force_error = StandardError.new('boom')
        error = nil
        begin
          service.book(user:, provider:, slot:, params:)
        rescue => e
          error = e
        end
        expect(error).to be_a(described_class::AlreadyLogged)
      end
    end
  end
end
