# frozen_string_literal: true

require 'rails_helper'
require 'unified_health_data/models/prescription'
require 'unified_health_data/adapters/oracle_health_prescription_adapter'
require 'unified_health_data/facility_service'

# Measurement-only OH "submitted stuck > 3 days" signal. OH collapses
# "submitted" after the 3-day in-flight window, so this must be captured during parse
# from the raw order-Task. These specs prove it is ungated, PII/PHI-safe, and does not
# fire once a dispense has cleared the refill or while still within the window.
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
    allow(Flipper).to receive(:enabled?).and_call_original
    allow(Flipper).to receive(:enabled?).with(:mhv_medications_stuck_status_logging, anything).and_return(true)

    facility = instance_double(HealthFacility, name: 'Portland VA Medical Center')
    allow(HealthFacility).to receive(:find_by).and_return(facility)
    facility_tz_service = instance_double(UnifiedHealthData::FacilityService)
    allow(UnifiedHealthData::FacilityService).to receive(:new).and_return(facility_tz_service)
    allow(facility_tz_service).to receive(:get_facility_timezone).and_return('America/Los_Angeles')
  end

  def capture_stuck_payload
    payload = nil
    allow(Rails.logger).to receive(:info) do |arg|
      payload = arg if arg.is_a?(Hash) && arg[:message] == 'UHD prescription stuck status'
    end
    yield
    payload
  end

  describe '#log_oh_submitted_stuck' do
    it 'emits a stuck.submitted counter tagged source_ehr:OH for a requested Task older than the window' do
      payload = capture_stuck_payload do
        travel_to(now) do
          subject.parse(fhir_resource_with_task(task_status: 'requested', task_date: '2025-06-10T00:00:00Z'))
        end
      end

      expect(StatsD).to have_received(:increment).with(
        'api.uhd.prescriptions.stuck.submitted',
        tags: array_including('source_ehr:OH', 'days_bucket:15-30')
      )
      expect(payload).to include(metric: 'submitted', source_ehr: 'OH', days_stuck: 16)
      expect(payload[:rx_id_hash]).to eq(Digest::SHA256.hexdigest('12345'))
    end

    it 'does not emit while the Task is still within the 3-day window' do
      travel_to(now) do
        subject.parse(fhir_resource_with_task(task_status: 'requested', task_date: '2025-06-25T00:00:00Z'))
      end

      expect(StatsD).not_to have_received(:increment).with('api.uhd.prescriptions.stuck.submitted', anything)
    end

    it 'does not emit when a subsequent dispense has fulfilled the refill' do
      travel_to(now) do
        subject.parse(
          fhir_resource_with_task(
            task_status: 'requested', task_date: '2025-06-10T00:00:00Z',
            dispenses: [{ status: 'completed', when_handed_over: '2025-06-15T00:00:00Z' }]
          )
        )
      end

      expect(StatsD).not_to have_received(:increment).with('api.uhd.prescriptions.stuck.submitted', anything)
    end

    it 'does not emit when the flag is disabled' do
      allow(Flipper).to receive(:enabled?).with(:mhv_medications_stuck_status_logging, anything).and_return(false)

      travel_to(now) do
        subject.parse(fhir_resource_with_task(task_status: 'requested', task_date: '2025-06-10T00:00:00Z'))
      end

      expect(StatsD).not_to have_received(:increment).with('api.uhd.prescriptions.stuck.submitted', any_args)
    end
  end
end
