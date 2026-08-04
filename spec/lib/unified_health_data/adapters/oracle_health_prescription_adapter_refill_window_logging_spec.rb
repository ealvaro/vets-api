# frozen_string_literal: true

require 'rails_helper'
require 'unified_health_data/models/prescription'
require 'unified_health_data/adapters/oracle_health_prescription_adapter'
require 'unified_health_data/facility_service'

# Measurement-only instrumentation for the OH in-flight refill "window" behavior.
# These specs prove the logging fires for the two measurement events, is fully
# gated by the :mhv_medications_oh_refill_window_logging flag, emits no PII/PHI,
# and never changes classification output.
describe UnifiedHealthData::Adapters::OracleHealthPrescriptionAdapter do
  include ActiveSupport::Testing::TimeHelpers
  include FhirResourceBuilder

  subject { described_class.new }

  let(:now) { Time.zone.parse('2025-06-26T00:00:00Z') }

  before do
    allow(Rails.cache).to receive(:exist?).and_return(false)
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:warn)
    allow(StatsD).to receive(:increment)

    facility = instance_double(HealthFacility, name: 'Portland VA Medical Center')
    allow(HealthFacility).to receive(:find_by).and_return(facility)

    facility_tz_service = instance_double(UnifiedHealthData::FacilityService)
    allow(UnifiedHealthData::FacilityService).to receive(:new).and_return(facility_tz_service)
    allow(facility_tz_service).to receive(:get_facility_timezone).and_return('America/Los_Angeles')
  end

  # Captures the structured refill-window log payload emitted (if any).
  def capture_window_payload
    payload = nil
    allow(Rails.logger).to receive(:info) do |arg|
      payload = arg if arg.is_a?(Hash) && arg[:message] == described_class::REFILL_WINDOW_LOG_MESSAGE
    end
    yield
    payload
  end

  context 'when :mhv_medications_oh_refill_window_logging is enabled' do
    before do
      allow(Flipper).to receive(:enabled?).and_call_original
      allow(Flipper).to receive(:enabled?)
        .with(:mhv_medications_oh_refill_window_logging, anything).and_return(true)
    end

    describe 'event A: window-dropped (task older than window, no subsequent dispense)' do
      it 'emits a window_dropped log and StatsD counter' do
        travel_to(now) do
          payload = capture_window_payload do
            subject.parse(fhir_resource_with_task(task_status: 'requested',
                                                  task_date: '2025-06-10T00:00:00Z'))
          end

          expect(payload).to include(
            event: 'window_dropped',
            has_subsequent_dispense: false,
            days_since_submit: 16,
            days_to_dispense: nil,
            task_status: 'requested',
            task_intent: 'order',
            task_type: 'refill',
            source_system: 'oracle-health'
          )
        end

        expect(StatsD).to have_received(:increment)
          .with(described_class::STATSD_WINDOW_DROPPED,
                tags: array_including('task_type:refill', 'days_bucket:15-30'))
      end
    end

    describe 'event B: dispense-cleared (subsequent completed dispense exists)' do
      it 'emits a dispense_cleared log with correct days_to_dispense and StatsD counter' do
        travel_to(now) do
          payload = capture_window_payload do
            subject.parse(
              fhir_resource_with_task(
                task_status: 'requested',
                task_date: '2025-06-10T00:00:00Z',
                dispenses: [{ status: 'completed', when_handed_over: '2025-06-20T00:00:00Z' }]
              )
            )
          end

          expect(payload).to include(
            event: 'dispense_cleared',
            has_subsequent_dispense: true,
            days_to_dispense: 10,
            days_since_submit: 16
          )
        end

        expect(StatsD).to have_received(:increment)
          .with(described_class::STATSD_DISPENSE_CLEARED,
                tags: array_including('task_type:refill', 'days_bucket:8-14'))
      end

      it 'does not emit window_dropped when a subsequent dispense exists' do
        travel_to(now) do
          subject.parse(
            fhir_resource_with_task(
              task_status: 'requested',
              task_date: '2025-06-10T00:00:00Z',
              dispenses: [{ status: 'completed', when_handed_over: '2025-06-20T00:00:00Z' }]
            )
          )
        end

        expect(StatsD).not_to have_received(:increment).with(described_class::STATSD_WINDOW_DROPPED, anything)
      end
    end

    describe 'PII/PHI safety' do
      it 'hashes the prescription id and logs no drug/sig/identifier fields' do
        payload = nil
        travel_to(now) do
          payload = capture_window_payload do
            subject.parse(fhir_resource_with_task(task_status: 'requested',
                                                  task_date: '2025-06-10T00:00:00Z'))
          end
        end

        expect(payload[:rx_id_hash]).to eq(Digest::SHA256.hexdigest('12345'))
        expect(payload[:rx_id_hash]).not_to eq('12345')

        forbidden_keys = %i[prescription_name prescription_number instructions drug_name patient_name icn edipi id]
        expect(payload.keys & forbidden_keys).to be_empty

        # base_fhir_resource carries a drug name and sig — neither may appear in any value.
        expect(payload.values).not_to include('Test Medication')
        expect(payload.values).not_to include('Take as directed')
        expect(payload.values.map(&:to_s)).not_to include(a_string_including('12345'))
      end
    end

    describe 'in-window in-flight refill (no dispense, within window)' do
      it 'emits nothing' do
        travel_to(now) do
          subject.parse(fhir_resource_with_task(task_status: 'requested',
                                                task_date: '2025-06-25T00:00:00Z'))
        end

        expect(StatsD).not_to have_received(:increment).with(described_class::STATSD_WINDOW_DROPPED, anything)
        expect(StatsD).not_to have_received(:increment).with(described_class::STATSD_DISPENSE_CLEARED, anything)
      end
    end
  end

  context 'when :mhv_medications_oh_refill_window_logging is disabled' do
    before do
      allow(Flipper).to receive(:enabled?).and_call_original
      allow(Flipper).to receive(:enabled?)
        .with(:mhv_medications_oh_refill_window_logging, anything).and_return(false)
    end

    it 'emits no measurement logs or counters' do
      travel_to(now) do
        subject.parse(fhir_resource_with_task(task_status: 'requested', task_date: '2025-06-10T00:00:00Z'))
      end

      expect(Rails.logger).not_to have_received(:info)
        .with(hash_including(message: described_class::REFILL_WINDOW_LOG_MESSAGE))
      expect(StatsD).not_to have_received(:increment).with(described_class::STATSD_WINDOW_DROPPED, anything)
      expect(StatsD).not_to have_received(:increment).with(described_class::STATSD_DISPENSE_CLEARED, anything)
    end
  end

  describe 'classification output is unchanged by the logging flag' do
    def classification_for(logging_enabled)
      allow(Flipper).to receive(:enabled?).and_call_original
      allow(Flipper).to receive(:enabled?)
        .with(:mhv_medications_oh_refill_window_logging, anything).and_return(logging_enabled)

      result = travel_to(now) do
        subject.parse(
          fhir_resource_with_task(
            task_status: 'requested',
            task_date: '2025-06-10T00:00:00Z',
            dispenses: [{ status: 'completed', when_handed_over: '2025-06-20T00:00:00Z' }]
          )
        )
      end

      {
        refill_status: result.refill_status,
        refill_submit_date: result.refill_submit_date,
        is_refillable: result.is_refillable,
        disp_status: result.disp_status,
        dispenses: result.dispenses
      }
    end

    it 'produces identical classification with the flag on vs off' do
      expect(classification_for(true)).to eq(classification_for(false))
    end
  end
end
