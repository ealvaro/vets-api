# frozen_string_literal: true

require 'rails_helper'
require 'unified_health_data/models/prescription'
require 'unified_health_data/adapters/oracle_health_prescription_adapter'
require 'unified_health_data/facility_service'
require 'lighthouse/facilities/v1/client'

describe UnifiedHealthData::Adapters::OracleHealthPrescriptionAdapter do
  include ActiveSupport::Testing::TimeHelpers
  include FhirResourceBuilder

  subject { described_class.new }

  before do
    allow(Rails.cache).to receive(:exist?).and_return(false)
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:warn)
    facility = instance_double(HealthFacility, name: 'Portland VA Medical Center')
    allow(HealthFacility).to receive(:find_by).and_return(facility)

    # Stub facility timezone service for expiration date normalization
    facility_tz_service = instance_double(UnifiedHealthData::FacilityService)
    allow(UnifiedHealthData::FacilityService).to receive(:new).and_return(facility_tz_service)
    allow(facility_tz_service).to receive(:get_facility_timezone) do |station_number|
      expect(station_number).to match(/^\d{3}$/)
      'America/Los_Angeles'
    end
  end

  describe '#parse' do
    context 'with valid resource' do
      it 'returns a UnifiedHealthData::Prescription object with correct id' do
        result = subject.parse(base_fhir_resource)

        expect(result).to be_a(UnifiedHealthData::Prescription)
        expect(result.id).to eq('12345')
        expect(result.source_ehr).to eq('OH')
      end

      it 'sets source_ehr to OH even when station_number is nil' do
        resource = fhir_resource(source: 'VA')
        resource['contained'] = [] # No dispenses means no station_number
        result = subject.parse(resource)

        expect(result.station_number).to be_nil
        expect(result.source_ehr).to eq('OH')
      end

      it 'returns nil for nil resource' do
        expect(subject.parse(nil)).to be_nil
      end

      it 'returns nil for resource missing id' do
        resource = base_fhir_resource.except('id')
        expect(subject.parse(resource)).to be_nil
      end

      it 'logs error and returns nil when parsing raises an error' do
        adapter = described_class.new
        allow(adapter).to receive(:extract_refill_date).and_raise(StandardError, 'Test error')
        allow(Rails.logger).to receive(:error)

        result = adapter.parse(base_fhir_resource)

        expect(result).to be_nil
        expect(Rails.logger).to have_received(:error).with('Error parsing Oracle Health prescription: Test error')
      end
    end

    context 'with prescription source classification' do
      it 'sets prescription_source to VA for VA prescriptions' do
        result = subject.parse(fhir_resource(source: 'VA'))
        expect(result.prescription_source).to eq('VA')
      end

      it 'sets prescription_source to NV for documented/non-VA medications' do
        result = subject.parse(fhir_resource(source: 'NV'))
        expect(result.prescription_source).to eq('NV')
      end

      it 'sets prescription_source to NV for unclassified medications' do
        result = subject.parse(base_fhir_resource)
        expect(result.prescription_source).to eq('NV')
      end
    end

    context 'when filtering medications' do
      it 'filters out inpatient medications' do
        resource = base_fhir_resource.merge(
          'category' => [{ 'coding' => [{ 'code' => 'inpatient' }] }]
        )
        expect(subject.parse(resource)).to be_nil
      end

      it 'filters out pharmacy charges medications' do
        resource = base_fhir_resource.merge(
          'category' => [{ 'coding' => [{ 'code' => 'charge-only' }] }]
        )
        expect(subject.parse(resource)).to be_nil
      end

      it 'filters out clinic-administered medications' do
        resource = base_fhir_resource.merge(
          'reportedBoolean' => false,
          'intent' => 'order',
          'category' => [{ 'coding' => [{ 'code' => 'outpatient' }] }]
        )
        expect(subject.parse(resource)).to be_nil
      end

      it 'filters out cancelled medications by default' do
        resource = base_fhir_resource.merge('status' => 'cancelled')
        expect(subject.parse(resource)).to be_nil
      end

      it 'filters out entered-in-error medications by default' do
        resource = base_fhir_resource.merge('status' => 'entered-in-error')
        expect(subject.parse(resource)).to be_nil
      end

      it 'uses configured filtered_statuses from Settings when present' do
        allow(Settings.mhv.uhd).to receive(:medication_filtered_statuses).and_return('cancelled,stopped')
        adapter = described_class.new

        expect(adapter.parse(base_fhir_resource.merge('status' => 'cancelled'))).to be_nil
        expect(adapter.parse(base_fhir_resource.merge('status' => 'stopped'))).to be_nil
        expect(adapter.parse(base_fhir_resource.merge('status' => 'entered-in-error'))).not_to be_nil
      end

      it 'disables status filtering when configured as "none"' do
        allow(Settings.mhv.uhd).to receive(:medication_filtered_statuses).and_return('none')
        adapter = described_class.new

        expect(adapter.parse(base_fhir_resource.merge('status' => 'cancelled'))).not_to be_nil
        expect(adapter.parse(base_fhir_resource.merge('status' => 'entered-in-error'))).not_to be_nil
      end

      it 'does not filter active medications' do
        resource = base_fhir_resource.merge('status' => 'active')
        expect(subject.parse(resource)).not_to be_nil
      end
    end

    context 'with refillability' do
      it 'marks VA prescription as refillable when active with refills and not expired' do
        resource = fhir_resource(status: 'active', refills: 5, expiration: 1.year.from_now, source: 'VA')
        result = subject.parse(resource)
        expect(result.is_refillable).to be true
      end

      it 'marks prescription as not refillable when non-VA' do
        result = subject.parse(fhir_resource(refills: 5, source: 'NV'))
        expect(result.is_refillable).to be false
      end

      it 'marks prescription as not refillable when status is not active' do
        result = subject.parse(fhir_resource(status: 'completed'))
        expect(result.is_refillable).to be false
      end

      it 'marks prescription as not refillable when expired' do
        result = subject.parse(fhir_resource(expiration: 1.day.ago))
        expect(result.is_refillable).to be false
      end

      it 'marks prescription as not refillable when no refills remaining' do
        result = subject.parse(fhir_resource(refills: 0))
        expect(result.is_refillable).to be false
      end

      it 'marks prescription as not refillable when most recent dispense is in-progress' do
        result = subject.parse(fhir_resource(refills: 5, dispense_status: 'in-progress'))
        expect(result.is_refillable).to be false
      end

      it 'marks prescription as not refillable when no expiration date exists' do
        resource = fhir_resource(status: 'active', refills: 5)
        resource['dispenseRequest'].delete('validityPeriod')

        result = subject.parse(resource)
        expect(result.is_refillable).to be false
      end

      it 'marks prescription as not refillable when facility cannot be resolved' do
        allow(HealthFacility).to receive(:find_by).and_return(nil)
        allow_any_instance_of(Lighthouse::Facilities::V1::Client).to receive(:get_facilities).and_return([])

        resource = fhir_resource(status: 'active', refills: 5, expiration: 1.year.from_now, source: 'VA')
        result = subject.parse(resource)
        expect(result.facility_name).to be_nil
        expect(result.is_refillable).to be false
      end
    end

    context 'with renewability' do
      let(:renewable_resource) do
        fhir_resource(
          status: 'active',
          refills: 1,
          expiration: 30.days.ago,
          source: 'VA'
        ).merge(
          'contained' => [
            {
              'resourceType' => 'MedicationDispense',
              'id' => 'dispense-1',
              'status' => 'completed',
              'whenHandedOver' => '2025-01-15T10:00:00Z'
            },
            {
              'resourceType' => 'MedicationDispense',
              'id' => 'dispense-2',
              'status' => 'completed',
              'whenHandedOver' => '2025-01-20T10:00:00Z'
            }
          ]
        )
      end

      it 'marks VA prescription as renewable when all conditions are met' do
        result = subject.parse(renewable_resource)
        expect(result.is_renewable).to be true
      end

      it 'marks prescription as not renewable when status is not active' do
        resource = renewable_resource.merge('status' => 'completed')
        result = subject.parse(resource)
        expect(result.is_renewable).to be false
      end

      it 'marks prescription as not renewable when non-VA medication' do
        result = subject.parse(fhir_resource(source: 'NV'))
        expect(result.is_renewable).to be false
      end

      it 'marks prescription as not renewable when no dispenses exist' do
        resource = renewable_resource.merge('contained' => [])
        result = subject.parse(resource)
        expect(result.is_renewable).to be false
      end

      it 'marks prescription as not renewable when expired more than 120 days ago' do
        resource = fhir_resource(
          status: 'active',
          refills: 1,
          expiration: 150.days.ago,
          source: 'VA',
          dispense_status: 'completed'
        )

        result = subject.parse(resource)
        expect(result.is_renewable).to be false
      end

      it 'is not renewable when a dispense is in-progress and the Rx is not expired (Gate 7)' do
        # Gate 7 blocks renewal during genuine in-flight processing. A completed dispense makes
        # Gate 3 pass and refills are exhausted, so an added in-progress dispense is the only thing
        # that can drive renewability to false here.
        resource = fhir_resource(status: 'active', refills: 0, expiration: 30.days.from_now,
                                 source: 'VA', dispense_status: 'completed')
        resource['contained'] << { 'resourceType' => 'MedicationDispense', 'id' => 'dispense-2',
                                   'status' => 'in-progress', 'whenHandedOver' => nil,
                                   'location' => { 'display' => '648' } }

        result = subject.parse(resource)
        expect(result.is_renewable).to be false
      end

      it 'is renewable when expired within 120 days despite an in-progress dispense' do
        # Oracle Health keeps mr_status='active' past legal expiration; a refill/dispense in flight
        # against an expired Rx will FAIL the OH Work Queue Monitor, so that doomed in-progress
        # dispense must not block renewal. The Rx should surface under "Renewal needed before refill".
        resource = fhir_resource(status: 'active', refills: 0, expiration: 30.days.ago,
                                 source: 'VA', dispense_status: 'completed')
        resource['contained'] << { 'resourceType' => 'MedicationDispense', 'id' => 'dispense-2',
                                   'status' => 'in-progress', 'whenHandedOver' => nil,
                                   'location' => { 'display' => '648' } }

        result = subject.parse(resource)
        expect(result.is_renewable).to be true
      end
    end

    context 'with renewal flow enabled' do
      let(:renewable_resource) do
        fhir_resource(
          status: 'active',
          refills: 1,
          expiration: 30.days.ago,
          source: 'VA'
        ).merge(
          'contained' => [
            {
              'resourceType' => 'MedicationDispense',
              'id' => 'dispense-1',
              'status' => 'completed',
              'whenHandedOver' => '2025-01-15T10:00:00Z'
            },
            {
              'resourceType' => 'MedicationDispense',
              'id' => 'dispense-2',
              'status' => 'completed',
              'whenHandedOver' => '2025-01-20T10:00:00Z'
            }
          ]
        )
      end

      it 'sets is_renewal_flow_enabled to false when facility cannot be resolved' do
        allow(HealthFacility).to receive(:find_by).and_return(nil)
        allow_any_instance_of(Lighthouse::Facilities::V1::Client).to receive(:get_facilities).and_return([])

        result = subject.parse(renewable_resource)
        expect(result.is_renewable).to be true
        expect(result.is_renewal_flow_enabled).to be false
      end
    end

    context 'with status normalization' do
      it 'maps active status to "active" refill_status' do
        result = subject.parse(fhir_resource(status: 'active'))
        expect(result.refill_status).to eq('active')
      end

      it 'maps on-hold status to "providerHold" refill_status' do
        resource = base_fhir_resource.merge('status' => 'on-hold')
        result = subject.parse(resource)
        expect(result.refill_status).to eq('providerHold')
      end

      it 'maps stopped status to "discontinued" refill_status' do
        allow(Settings.mhv.uhd).to receive(:medication_filtered_statuses).and_return('none')
        resource = base_fhir_resource.merge('status' => 'stopped')
        result = described_class.new.parse(resource)
        expect(result.refill_status).to eq('discontinued')
      end

      it 'maintains active status when no refills remain but expiration is in the future' do
        result = subject.parse(fhir_resource(status: 'active', refills: 0, dispense_status: nil))
        expect(result.refill_status).to eq('active')
      end

      it 'maps active to "refillinprocess" when most recent dispense is in-progress' do
        result = subject.parse(fhir_resource(status: 'active', dispense_status: 'in-progress'))
        expect(result.refill_status).to eq('refillinprocess')
      end

      it 'maps active to "expired" when past expiration date regardless of refills remaining' do
        result = subject.parse(fhir_resource(status: 'active', refills: 3, expiration: 1.day.ago, source: 'VA'))
        expect(result.refill_status).to eq('expired')
      end

      it 'maps active to "expired" over "refillinprocess" when past expiration with an in-progress dispense' do
        # OH has no 'expired' MedicationRequest status, so an expired Rx keeps mr_status='active';
        # an in-flight fill against it will FAIL the OH Work Queue Monitor, so expiration must win
        # over the in-progress dispense and the card must not offer a doomed re-refill.
        result = subject.parse(fhir_resource(status: 'active', refills: 3, expiration: 1.day.ago,
                                             source: 'VA', dispense_status: 'in-progress'))
        expect(result.refill_status).to eq('expired')
        expect(result.disp_status).to eq('Expired')
        expect(result.is_refillable).to be false
      end

      it 'maps active to "expired" when expired more than 120 days ago' do
        result = subject.parse(fhir_resource(status: 'active', refills: 0, expiration: 150.days.ago, source: 'VA'))
        expect(result.refill_status).to eq('expired')
        expect(result.disp_status).to eq('Expired')
      end

      it 'maps completed to "discontinued" when expired more than 120 days ago' do
        result = subject.parse(fhir_resource(status: 'completed', refills: 0, expiration: 150.days.ago, source: 'VA'))
        expect(result.refill_status).to eq('discontinued')
        expect(result.disp_status).to eq('Discontinued')
      end

      it 'maps completed to "discontinued" when expiration date is nil' do
        resource = fhir_resource(status: 'completed', refills: 0, source: 'VA')
        resource['dispenseRequest'].delete('validityPeriod')
        result = subject.parse(resource)
        expect(result.refill_status).to eq('discontinued')
        expect(result.disp_status).to eq('Discontinued')
      end

      # Characterization: today FHIR 'draft' collapses to Unknown via
      # draft->pending->DISP_UNKNOWN. Pin the bug so the fix visibly flips this example.
      it 'currently maps draft status to Unknown disp_status (BUG characterization)' do
        allow(Settings.mhv.uhd).to receive(:medication_filtered_statuses).and_return('none')
        resource = base_fhir_resource.merge('status' => 'draft')
        result = described_class.new.parse(resource)
        expect(result.refill_status).to eq('pending')
        expect(result.disp_status).to eq('Unknown') # <-- WRONG; documents the chain-break
      end

      # INTENDED behavior — currently FAILS until the source fix lands. Marked pending so CI
      # stays green while the intent is recorded; remove `pending:` when the fix is applied.
      it 'maps draft status to Pending disp_status',
         pending: 'BUG: draft->pending->DISP_UNKNOWN; fix map_refill_status_to_disp_status' do
        allow(Settings.mhv.uhd).to receive(:medication_filtered_statuses).and_return('none')
        resource = base_fhir_resource.merge('status' => 'draft')
        result = described_class.new.parse(resource)
        expect(result.refill_status).to eq('pending')
        expect(result.disp_status).to eq('Pending')
      end
    end

    context 'with disp_status mapping' do
      it 'maps active VA prescription to "Active" disp_status' do
        result = subject.parse(fhir_resource(status: 'active', source: 'VA'))
        expect(result.disp_status).to eq('Active')
      end

      it 'maps active non-VA prescription to "Active: Non-VA" disp_status' do
        result = subject.parse(fhir_resource(status: 'active', source: 'NV'))
        expect(result.disp_status).to eq('Active: Non-VA')
      end

      it 'maps on-hold to "Active: On hold" disp_status' do
        resource = base_fhir_resource.merge('status' => 'on-hold')
        result = subject.parse(resource)
        expect(result.disp_status).to eq('Active: On hold')
      end

      it 'maps in-progress dispense to "Active: Refill in Process" disp_status' do
        result = subject.parse(fhir_resource(status: 'active', refills: 3, dispense_status: 'in-progress'))
        expect(result.disp_status).to eq('Active: Refill in Process')
      end

      # The !is_non_va guard: a Non-VA med past expiration must NOT flip to Expired.
      it 'keeps a past-expiration Non-VA med as "Active: Non-VA" (does not expire)' do
        result = subject.parse(fhir_resource(status: 'active', refills: 0, expiration: 1.day.ago, source: 'NV'))
        expect(result.refill_status).to eq('active')
        expect(result.disp_status).to eq('Active: Non-VA')
      end
    end

    # Unknown sink + warn on unmapped upstream values.
    context 'with unknown / unmapped statuses' do
      before { allow(Settings.mhv.uhd).to receive(:medication_filtered_statuses).and_return('none') }

      it 'maps FHIR status "unknown" to Unknown disp_status without warning' do
        expect(Rails.logger).not_to receive(:warn).with(/Unexpected MedicationRequest status/)
        result = described_class.new.parse(base_fhir_resource.merge('status' => 'unknown'))
        expect(result.refill_status).to eq('unknown')
        expect(result.disp_status).to eq('Unknown')
      end

      it 'warns and defaults to Unknown for a bogus MedicationRequest status' do
        expect(Rails.logger).to receive(:warn).with(/Unexpected MedicationRequest status: bogus-status/)
        result = described_class.new.parse(base_fhir_resource.merge('status' => 'bogus-status'))
        expect(result.refill_status).to eq('unknown')
        expect(result.disp_status).to eq('Unknown')
      end

      it 'warns from map_refill_status_to_disp_status for an unmapped refill_status' do
        adapter = described_class.new
        expect(Rails.logger).to receive(:warn)
          .with(/Unexpected refill_status for disp_status mapping: surprise/)
        expect(adapter.send(:map_refill_status_to_disp_status, 'surprise', 'VA')).to eq('Unknown')
      end
    end

    # The cancelled/entered-in-error -> Discontinued arm is DEAD under prod
    # defaults (dropped at parse). It is only reachable when status filtering is disabled.
    context 'cancelled/entered-in-error discontinue branch (dead under defaults)' do
      it 'drops cancelled/entered-in-error before mapping under prod defaults (no Discontinued emitted)' do
        expect(subject.parse(base_fhir_resource.merge('status' => 'cancelled'))).to be_nil
        expect(subject.parse(base_fhir_resource.merge('status' => 'entered-in-error'))).to be_nil
      end

      it 'only reaches STATUS_DISCONTINUED for cancelled/entered-in-error when filtering is disabled' do
        allow(Settings.mhv.uhd).to receive(:medication_filtered_statuses).and_return('none')
        %w[cancelled entered-in-error].each do |st|
          result = described_class.new.parse(base_fhir_resource.merge('status' => st))
          expect(result.refill_status).to eq('discontinued')
          expect(result.disp_status).to eq('Discontinued')
        end
      end
    end

    context 'with refill submission tracking using Task resources' do
      # These fixtures use fixed mid-2025 Task dates. mhv_medications_management_improvements
      # is enabled by default in this spec (no global stub), so freeze time near the fixture
      # dates to keep them inside the in-flight staleness window that OracleHealthTaskHelper
      # applies when deriving refill_submit_date.
      around do |example|
        travel_to(Time.zone.parse('2025-06-26T00:00:00Z')) { example.run }
      end

      it 'sets submitted status when valid Task exists without subsequent dispense' do
        result = subject.parse(fhir_resource_with_task)

        expect(result.refill_status).to eq('submitted')
        expect(result.disp_status).to eq('Active: Submitted')
        expect(result.refill_submit_date).to eq('2025-06-24T21:05:53.000Z')
      end

      it 'ignores failed Task resources' do
        result = subject.parse(fhir_resource_with_task(task_status: 'failed'))

        expect(result.refill_status).to eq('active')
        expect(result.refill_submit_date).to be_nil
      end

      it 'ignores Task with wrong intent' do
        result = subject.parse(fhir_resource_with_task(task_intent: 'refill'))

        expect(result.refill_status).to eq('active')
        expect(result.refill_submit_date).to be_nil
      end

      it 'does not set submitted when dispense occurs after task' do
        resource = fhir_resource_with_task(
          task_date: '2025-06-24T10:00:00.000Z',
          dispenses: [
            {
              status: 'completed',
              when_prepared: '2025-06-24T12:00:00.000Z',
              when_handed_over: '2025-06-24T14:00:00.000Z'
            }
          ]
        )

        result = subject.parse(resource)

        expect(result.refill_status).to eq('active')
        expect(result.refill_submit_date).to be_nil
      end

      it 'sets submitted when dispense occurs before task' do
        resource = fhir_resource_with_task(
          task_date: '2025-06-24T10:00:00.000Z',
          dispenses: [
            {
              status: 'completed',
              when_prepared: '2025-06-20T12:00:00.000Z',
              when_handed_over: '2025-06-20T14:00:00.000Z'
            }
          ]
        )

        result = subject.parse(resource)

        expect(result.refill_status).to eq('submitted')
        expect(result.refill_submit_date).to eq('2025-06-24T10:00:00.000Z')
      end

      it 'keeps submitted status when in-progress dispense occurs after task' do
        resource = fhir_resource_with_task(
          task_date: '2025-06-24T10:00:00.000Z',
          dispenses: [
            {
              status: 'in-progress',
              when_prepared: '2025-06-25T12:00:00.000Z',
              when_handed_over: nil
            }
          ]
        )

        result = subject.parse(resource)

        expect(result.refill_status).to eq('submitted')
        expect(result.refill_submit_date).to eq('2025-06-24T10:00:00.000Z')
      end

      it 'keeps submitted status when preparation dispense occurs after task' do
        resource = fhir_resource_with_task(
          task_date: '2025-06-24T10:00:00.000Z',
          dispenses: [
            {
              status: 'preparation',
              when_prepared: '2025-06-25T12:00:00.000Z',
              when_handed_over: nil
            }
          ]
        )

        result = subject.parse(resource)

        expect(result.refill_status).to eq('submitted')
        expect(result.refill_submit_date).to eq('2025-06-24T10:00:00.000Z')
      end

      it 'keeps submitted status when on-hold dispense occurs after task' do
        resource = fhir_resource_with_task(
          task_date: '2025-06-24T10:00:00.000Z',
          dispenses: [
            {
              status: 'on-hold',
              when_prepared: '2025-06-25T12:00:00.000Z',
              when_handed_over: nil
            }
          ]
        )

        result = subject.parse(resource)

        expect(result.refill_status).to eq('submitted')
        expect(result.refill_submit_date).to eq('2025-06-24T10:00:00.000Z')
      end
    end

    # Order-intent (refill) most-recent-wins. Mirrors the renewal
    # 'selects the most recent renewal Task when multiple exist' test, but for intent='order',
    # which is the path veterans actually hit on refill. Guards the date-compare bug class:
    # an older order-Task from history must not flip the current refill status.
    context 'with multiple order-intent refill Tasks (most-recent-wins)' do
      around do |example|
        travel_to(Time.zone.parse('2025-06-26T00:00:00Z')) { example.run }
      end

      let(:fresh_date) { '2025-06-25T00:00:00.000Z' } # 1 day ago  (inside 3-day window)
      let(:older_in_window_date) { '2025-06-24T00:00:00.000Z' } # 2 days ago (inside window)
      let(:stale_date) { '2025-06-16T00:00:00.000Z' } # 10 days ago (outside window)

      it 'selects the most recent order-Task by date when two in-window Tasks exist' do
        # Both Tasks are inside the staleness window, so only max_by ordering can pick the winner.
        resource = fhir_resource_with_task(task_date: older_in_window_date)
        resource['contained'] << fhir_task('requested', 'order', fresh_date, '12345')

        result = subject.parse(resource)

        expect(result.refill_status).to eq('submitted')
        expect(result.disp_status).to eq('Active: Submitted')
        expect(result.refill_submit_date).to eq(fresh_date)
      end

      it 'ignores a stale historical order-Task and pins the fresh one (no date flip)' do
        # stale (10d, outside window) + fresh (1d, inside window). If max_by wrongly picked the
        # stale Task the med would fall back to plain Active with no submit date.
        resource = fhir_resource_with_task(task_date: stale_date)
        resource['contained'] << fhir_task('requested', 'order', fresh_date, '12345')

        result = subject.parse(resource)

        expect(result.refill_status).to eq('submitted')
        expect(result.disp_status).to eq('Active: Submitted')
        expect(result.refill_submit_date).to eq(fresh_date)
      end

      # Ambient-history immunity: a stale order-Task (20d) plus a completed
      # dispense must yield the SAME output as a plain active med with no Task, in BOTH flag states.
      [true, false].each do |flag_on|
        it "ignores an ambient stale order-Task and matches the no-Task baseline (flag=#{flag_on})" do
          allow(Flipper).to receive(:enabled?).and_call_original
          allow(Flipper).to receive(:enabled?)
            .with(:mhv_medications_management_improvements, anything).and_return(flag_on)

          stale = '2025-06-06T00:00:00.000Z' # 20 days ago, well outside the 3-day window
          resource = fhir_resource_with_task(
            task_date: stale,
            dispenses: [{ status: 'completed',
                          when_prepared: '2025-06-05T00:00:00.000Z',
                          when_handed_over: '2025-06-05T00:00:00.000Z' }]
          )

          result = subject.parse(resource)

          # Identical to the no-Task active baseline:
          expect(result.refill_status).to eq('active')
          expect(result.disp_status).to eq('Active')
          expect(result.refill_submit_date).to be_nil
        end
      end

      # Cross-reference contamination guard for intent='order'. A fresh order-Task
      # pointing at a DIFFERENT MedicationRequest must not pin THIS Rx as Submitted.
      it 'ignores a fresh order-Task whose focus.reference points at a different MedicationRequest' do
        resource = fhir_resource_with_task(task_date: '2025-06-25T00:00:00.000Z')
        resource['contained'].first['focus']['reference'] = 'MedicationRequest/99999'

        result = subject.parse(resource)

        expect(result.refill_status).to eq('active')
        expect(result.disp_status).to eq('Active')
        expect(result.refill_submit_date).to be_nil
      end
    end

    # RC1a FIX: an in-flight refill lifecycle order-Task (accepted / in-progress /
    # completed) with no subsequent dispense should map to 'refillinprocess'
    # (Active: Refill in Process) when the medications management improvements flag
    # is enabled, and should block re-refill. When the flag is off the prior
    # behavior is preserved (only 'requested' is honored, as 'submitted').
    context 'in-flight order-Task without dispense (RC1a)' do
      context 'when mhv_medications_management_improvements is enabled' do
        let(:in_window_task_date) { 2.days.ago.utc.iso8601 }

        before do
          allow(Flipper).to receive(:enabled?).and_call_original
          allow(Flipper).to receive(:enabled?)
            .with(:mhv_medications_management_improvements, anything).and_return(true)
        end

        it 'maps a completed refill Task to refillinprocess and blocks re-refill' do
          result = subject.parse(fhir_resource_with_task(task_status: 'completed', task_date: in_window_task_date))

          expect(result.refill_status).to eq('refillinprocess')
          expect(result.disp_status).to eq('Active: Refill in Process')
          expect(result.is_refillable).to be false
          expect(result.refill_submit_date).to eq(in_window_task_date)
        end

        it 'maps an in-progress refill Task to refillinprocess' do
          result = subject.parse(fhir_resource_with_task(task_status: 'in-progress', task_date: in_window_task_date))

          expect(result.refill_status).to eq('refillinprocess')
          expect(result.disp_status).to eq('Active: Refill in Process')
          expect(result.is_refillable).to be false
        end

        it 'maps an accepted refill Task to refillinprocess' do
          result = subject.parse(fhir_resource_with_task(task_status: 'accepted', task_date: in_window_task_date))

          expect(result.refill_status).to eq('refillinprocess')
          expect(result.disp_status).to eq('Active: Refill in Process')
          expect(result.is_refillable).to be false
        end

        it 'still maps a requested order-Task to submitted' do
          result = subject.parse(fhir_resource_with_task(task_status: 'requested', task_date: in_window_task_date))

          expect(result.refill_status).to eq('submitted')
          expect(result.disp_status).to eq('Active: Submitted')
        end

        it 'leaves terminal/other order-Task statuses as active' do
          %w[failed rejected cancelled].each do |status|
            result = subject.parse(fhir_resource_with_task(task_status: status, task_date: in_window_task_date))

            expect(result.refill_status).to eq('active')
            expect(result.disp_status).to eq('Active')
          end
        end
      end

      context 'when mhv_medications_management_improvements is disabled' do
        before do
          allow(Flipper).to receive(:enabled?).and_call_original
          allow(Flipper).to receive(:enabled?)
            .with(:mhv_medications_management_improvements, anything).and_return(false)
        end

        it 'leaves a completed refill Task as plain active' do
          result = subject.parse(fhir_resource_with_task(task_status: 'completed'))

          expect(result.refill_status).to eq('active')
          expect(result.disp_status).to eq('Active')
          expect(result.refill_submit_date).to be_nil
        end

        it 'still maps a requested order-Task to submitted' do
          result = subject.parse(fhir_resource_with_task(task_status: 'requested', task_date: 2.days.ago.utc.iso8601))

          expect(result.refill_status).to eq('submitted')
          expect(result.disp_status).to eq('Active: Submitted')
        end
      end
    end

    # In-flight refill Task staleness window (Issue 1): once an honored in-flight
    # order-Task ages past REFILL_IN_FLIGHT_WINDOW_DAYS (3) with no fulfilling
    # dispense, the status falls back to the normalized MedicationRequest status
    # and refill_submit_date is dropped, so a med does not display an in-flight
    # refill state indefinitely. The window is always enforced, regardless of the flag.
    context 'in-flight refill Task staleness window' do
      context 'when mhv_medications_management_improvements is enabled' do
        before do
          allow(Flipper).to receive(:enabled?).and_call_original
          allow(Flipper).to receive(:enabled?)
            .with(:mhv_medications_management_improvements, anything).and_return(true)
        end

        it 'honors an in-flight Task just inside the 3-day window' do
          result = subject.parse(
            fhir_resource_with_task(task_status: 'completed', task_date: (3.days.ago + 1.hour).utc.iso8601)
          )

          expect(result.refill_status).to eq('refillinprocess')
          expect(result.disp_status).to eq('Active: Refill in Process')
        end

        it 'drops a stale refillinprocess Task back to active and clears refill_submit_date' do
          result = subject.parse(
            fhir_resource_with_task(task_status: 'completed', task_date: 20.days.ago.utc.iso8601)
          )

          expect(result.refill_status).to eq('active')
          expect(result.disp_status).to eq('Active')
          expect(result.refill_submit_date).to be_nil
        end

        it 'drops a stale submitted Task back to active and clears refill_submit_date' do
          result = subject.parse(
            fhir_resource_with_task(task_status: 'requested', task_date: 20.days.ago.utc.iso8601)
          )

          expect(result.refill_status).to eq('active')
          expect(result.disp_status).to eq('Active')
          expect(result.refill_submit_date).to be_nil
        end
      end

      context 'when mhv_medications_management_improvements is disabled' do
        before do
          allow(Flipper).to receive(:enabled?).and_call_original
          allow(Flipper).to receive(:enabled?)
            .with(:mhv_medications_management_improvements, anything).and_return(false)
        end

        it 'drops a stale requested Task back to active and clears refill_submit_date' do
          stale_date = 20.days.ago.utc.iso8601
          result = subject.parse(fhir_resource_with_task(task_status: 'requested', task_date: stale_date))

          expect(result.refill_status).to eq('active')
          expect(result.disp_status).to eq('Active')
          expect(result.refill_submit_date).to be_nil
        end

        it 'still honors a requested Task within the window as submitted' do
          fresh_date = 2.days.ago.utc.iso8601
          result = subject.parse(fhir_resource_with_task(task_status: 'requested', task_date: fresh_date))

          expect(result.refill_status).to eq('submitted')
          expect(result.disp_status).to eq('Active: Submitted')
          expect(result.refill_submit_date).to eq(fresh_date)
        end
      end
    end

    # An in-flight refill order-Task is an overlay that only applies on top of an
    # otherwise-active med. It must never resurrect a med whose real lifecycle is
    # terminal or paused (discontinued, expired, on-hold, pending). A 'requested'
    # Task within the staleness window is honored under every flag/path combination,
    # so these cases isolate the base-lifecycle guard: without it each med would
    # render "Active: Submitted" and carry a refill_submit_date.
    context 'in-flight refill Task cannot mask a non-active medication' do
      let(:fresh_task_date) { 2.days.ago.utc.iso8601 }

      def resource_with_requested_task(**overrides)
        fhir_resource_with_task(task_status: 'requested', task_date: fresh_task_date).merge(overrides)
      end

      it 'does not mask a discontinued (stopped) med as Active: Submitted' do
        result = subject.parse(resource_with_requested_task('status' => 'stopped'))

        expect(result.refill_status).to eq('discontinued')
        expect(result.disp_status).to eq('Discontinued')
        expect(result.refill_submit_date).to be_nil
      end

      it 'does not mask an on-hold med as Active: Submitted' do
        result = subject.parse(resource_with_requested_task('status' => 'on-hold'))

        expect(result.refill_status).to eq('providerHold')
        expect(result.disp_status).to eq('Active: On hold')
        expect(result.refill_submit_date).to be_nil
      end

      it 'does not mask a pending (draft) med as Active: Submitted' do
        result = subject.parse(resource_with_requested_task('status' => 'draft'))

        expect(result.refill_status).to eq('pending')
        expect(result.refill_submit_date).to be_nil
      end

      it 'does not mask an expired med as Active: Submitted' do
        resource = resource_with_requested_task
        resource['dispenseRequest']['validityPeriod']['end'] = 10.days.ago.utc.iso8601
        result = subject.parse(resource)

        expect(result.refill_status).to eq('expired')
        expect(result.disp_status).to eq('Expired')
        expect(result.refill_submit_date).to be_nil
      end

      it 'still applies the overlay to an active med (control)' do
        result = subject.parse(resource_with_requested_task)

        expect(result.refill_status).to eq('submitted')
        expect(result.disp_status).to eq('Active: Submitted')
        expect(result.refill_submit_date).to eq(fresh_task_date)
      end

      it 'suppresses the overlay on a non-active med regardless of the bandaid flag' do
        allow(Flipper).to receive(:enabled?).and_call_original
        allow(Flipper).to receive(:enabled?)
          .with(:mhv_mmi_refill_status_bandaid_temp, anything).and_return(true)

        result = subject.parse(resource_with_requested_task('status' => 'stopped'))

        expect(result.refill_status).to eq('discontinued')
        expect(result.refill_submit_date).to be_nil
      end
    end

    # extract_refill_status_upstream is the flag-off classification path: only a live
    # 'requested' order-Task with no subsequent dispense maps to 'submitted'; everything
    # else reflects the normalized upstream status. The suite enables
    # mhv_mmi_refill_status_bandaid_temp by default, so these stub it off to exercise it.
    context 'upstream classification path (bandaid flag disabled)' do
      before do
        allow(Flipper).to receive(:enabled?).and_call_original
        allow(Flipper).to receive(:enabled?)
          .with(:mhv_mmi_refill_status_bandaid_temp, anything).and_return(false)
      end

      it 'maps a requested order-Task with no subsequent dispense to submitted' do
        resource = fhir_resource_with_task(task_status: 'requested', task_date: 2.days.ago.utc.iso8601)

        result = subject.parse(resource)

        expect(result.refill_status).to eq('submitted')
        expect(result.disp_status).to eq('Active: Submitted')
      end

      it 'falls through to the normalized status when no order-Task is present' do
        result = subject.parse(base_fhir_resource)

        expect(result.refill_status).to eq('active')
      end
    end

    # Isolates Gate 7 (the re-refill block) in OracleHealthRefillHelper#refillable?.
    # Unlike the RC1a fixtures above, this resource carries a prior completed dispense
    # dated before the in-flight order-Task, so Gates 1-6 (non-VA, active, not expired,
    # refills remaining, a completed dispense exists, most-recent dispense not in
    # progress) all pass. That leaves the refill_status check in Gate 7 as the only
    # thing that can drive is_refillable to false. The flag-off case is the control:
    # the same fixture resolves to 'active', Gate 7 does not fire, and the med is
    # refillable -- proving the flag-on 'false' is attributable specifically to Gate 7.
    # Recent relative dates keep this valid regardless of any future in-flight window.
    context 'Gate 7 re-refill block with prior dispense (Gates 1-6 pass)' do
      let(:task_date) { 2.days.ago.utc.iso8601 }
      let(:prior_dispense_date) { 5.days.ago.utc.iso8601 }
      let(:resource_with_prior_dispense) do
        fhir_resource_with_task(
          task_status: 'completed',
          task_date:,
          dispenses: [
            {
              status: 'completed',
              when_prepared: prior_dispense_date,
              when_handed_over: prior_dispense_date,
              location: '648'
            }
          ]
        )
      end

      context 'when mhv_medications_management_improvements is enabled' do
        before do
          allow(Flipper).to receive(:enabled?).and_call_original
          allow(Flipper).to receive(:enabled?)
            .with(:mhv_medications_management_improvements, anything).and_return(true)
        end

        it 'blocks re-refill via Gate 7 when status is refillinprocess' do
          result = subject.parse(resource_with_prior_dispense)

          expect(result.refill_status).to eq('refillinprocess')
          expect(result.is_refillable).to be false
        end
      end

      context 'when mhv_medications_management_improvements is disabled' do
        before do
          allow(Flipper).to receive(:enabled?).and_call_original
          allow(Flipper).to receive(:enabled?)
            .with(:mhv_medications_management_improvements, anything).and_return(false)
        end

        it 'remains refillable because status resolves to active (Gate 7 not triggered)' do
          result = subject.parse(resource_with_prior_dispense)

          expect(result.refill_status).to eq('active')
          expect(result.is_refillable).to be true
        end
      end
    end

    context 'with renewal submission tracking using Task resources' do
      it 'sets renewal_submitted_timestamp when valid renewal Task exists' do
        result = subject.parse(fhir_resource_with_renewal_task)

        expect(result.renewal_submitted_timestamp).to be_a(Integer)
        expect(result.renewal_submitted_timestamp).to be > 0
      end

      it 'ignores renewal Task with failed status' do
        result = subject.parse(fhir_resource_with_renewal_task(task_status: 'failed'))

        expect(result.renewal_submitted_timestamp).to be_nil
      end

      it 'ignores Task with wrong task-type extension' do
        result = subject.parse(fhir_resource_with_renewal_task(task_type: 'refill'))

        expect(result.renewal_submitted_timestamp).to be_nil
      end

      it 'sets renewal_submitted_timestamp when no task-type extension is present' do
        resource = fhir_resource_with_renewal_task
        # Remove meta extension to test fallback behavior
        resource['contained'].first.delete('meta')

        result = subject.parse(resource)

        expect(result.renewal_submitted_timestamp).to be_a(Integer)
        expect(result.renewal_submitted_timestamp).to be > 0
      end

      it 'does not set renewal_submitted_timestamp for refill Tasks (intent=order)' do
        result = subject.parse(fhir_resource_with_task)

        expect(result.renewal_submitted_timestamp).to be_nil
      end

      it 'converts executionPeriod.start to epoch milliseconds correctly' do
        task_date = '2025-06-24T21:05:53.000Z'
        result = subject.parse(fhir_resource_with_renewal_task(task_date:))

        parsed_time = Time.zone.parse(task_date)
        expected_millis = (parsed_time.to_i * 1000) + (parsed_time.nsec / 1_000_000)
        expect(result.renewal_submitted_timestamp).to eq(expected_millis)
      end

      it 'preserves non-zero milliseconds when converting executionPeriod.start' do
        task_date = '2025-06-24T21:05:53.789Z'
        result = subject.parse(fhir_resource_with_renewal_task(task_date:))

        parsed_time = Time.zone.parse(task_date)
        expected_millis = (parsed_time.to_i * 1000) + (parsed_time.nsec / 1_000_000)
        expect(result.renewal_submitted_timestamp).to eq(expected_millis)
      end

      it 'ignores renewal Task with missing executionPeriod.start' do
        resource = fhir_resource_with_renewal_task
        resource['contained'].first.delete('executionPeriod')

        result = subject.parse(resource)

        expect(result.renewal_submitted_timestamp).to be_nil
      end

      it 'ignores renewal Task with non-matching focus reference' do
        resource = fhir_resource_with_renewal_task
        # Override focus to point to a different MedicationRequest
        resource['contained'].first['focus']['reference'] = 'MedicationRequest/99999'

        result = subject.parse(resource)

        expect(result.renewal_submitted_timestamp).to be_nil
      end

      it 'selects the most recent renewal Task when multiple exist' do
        resource = fhir_resource_with_renewal_task(task_date: '2025-06-20T10:00:00.000Z')
        newer_task = fhir_renewal_task('requested', '2025-06-25T10:00:00.000Z', '12345')
        resource['contained'] << newer_task

        result = subject.parse(resource)

        expected_millis = Time.zone.parse('2025-06-25T10:00:00.000Z').to_f * 1000
        expect(result.renewal_submitted_timestamp).to eq(expected_millis.to_i)
      end

      it 'sets both refill and renewal fields when both Task types exist' do
        travel_to(Time.zone.parse('2025-06-23T00:00:00Z')) do
          resource = fhir_resource_with_renewal_task
          refill_task = fhir_task('requested', 'order', '2025-06-22T10:00:00.000Z', '12345')
          resource['contained'] << refill_task

          result = subject.parse(resource)

          expect(result.renewal_submitted_timestamp).to be_a(Integer)
          expect(result.refill_submit_date).to eq('2025-06-22T10:00:00.000Z')
        end
      end
    end

    context 'with tracking information from extension-based shipping data' do
      let(:resource_with_extension_tracking) do
        {
          'id' => '20848812135',
          'medicationCodeableConcept' => {
            'text' => 'albuterol (albuterol 90 mcg inhaler [18g])',
            'coding' => [
              { 'system' => 'http://hl7.org/fhir/sid/ndc', 'code' => '00487-9801-01' }
            ]
          },
          'contained' => [
            {
              'resourceType' => 'MedicationDispense',
              'id' => '1854364634',
              'extension' => [
                {
                  'url' => 'http://va.gov/fhir/StructureDefinition/shipping-info',
                  'extension' => [
                    { 'url' => 'Tracking Number', 'valueString' => '9400111899223100000001' },
                    { 'url' => 'Delivery Service', 'valueString' => 'USPS' },
                    { 'url' => 'Shipped Date', 'valueString' => '2026-01-10 14:35:02.0' },
                    { 'url' => 'Prescription Name', 'valueString' => 'albuterol 90 mcg/inh Aerosol' },
                    { 'url' => 'NDC Code', 'valueString' => '00487-9801-01' },
                    { 'url' => 'Prescription Number', 'valueString' => 'RX-PLACER-001' }
                  ]
                }
              ]
            }
          ]
        }
      end

      it 'extracts tracking information from dispense extensions' do
        result = subject.parse(resource_with_extension_tracking)

        expect(result).to be_a(UnifiedHealthData::Prescription)
        expect(result.is_trackable).to be true
        expect(result.tracking).to be_an(Array)
        expect(result.tracking.length).to eq(1)

        tracking = result.tracking.first
        expect(tracking[:tracking_number]).to eq('9400111899223100000001')
        expect(tracking[:carrier]).to eq('USPS')
        expect(tracking[:complete_date_time]).to eq('2026-01-10 14:35:02.0')
        expect(tracking[:prescription_name]).to eq('albuterol 90 mcg/inh Aerosol')
        expect(tracking[:ndc_number]).to eq('00487-9801-01')
        expect(tracking[:prescription_number]).to eq('RX-PLACER-001')
        expect(tracking[:prescription_id]).to eq('20848812135')
      end

      it 'falls back to resource extraction when extension fields are missing' do
        resource_with_minimal_extension = {
          'id' => '12345',
          'medicationCodeableConcept' => {
            'text' => 'Test Medication',
            'coding' => [
              { 'system' => 'http://hl7.org/fhir/sid/ndc', 'code' => '11111-2222-33' }
            ]
          },
          'identifier' => [
            { 'system' => 'http://va.gov/identifier/rx-number', 'value' => '12345678' },
            { 'system' => 'http://va.gov/identifier/station-prefix', 'value' => '3001' }
          ],
          'contained' => [
            {
              'resourceType' => 'MedicationDispense',
              'extension' => [
                {
                  'url' => 'http://va.gov/fhir/StructureDefinition/shipping-info',
                  'extension' => [
                    { 'url' => 'Tracking Number', 'valueString' => '9999888877776666' }
                  ]
                }
              ]
            }
          ]
        }

        result = subject.parse(resource_with_minimal_extension)

        expect(result).to be_a(UnifiedHealthData::Prescription)
        tracking = result.tracking.first
        expect(tracking[:tracking_number]).to eq('9999888877776666')
        expect(tracking[:prescription_name]).to eq('Test Medication')
        expect(tracking[:prescription_number]).to eq('3001-12345678')
        expect(tracking[:ndc_number]).to eq('11111-2222-33')
      end
    end

    context 'with prescription number extraction' do
      it 'logs a warning when rx-number identifier is missing but station-prefix is present' do
        resource = base_fhir_resource.merge(
          'id' => '20848999999',
          'identifier' => [
            { 'system' => 'http://va.gov/identifier/station-prefix', 'value' => '3001' }
          ]
        )
        allow(Rails.logger).to receive(:warn)

        result = subject.parse(resource)

        expect(result.prescription_number).to be_nil
        expect(Rails.logger).to have_received(:warn).with(
          'Oracle Health prescription missing identifier',
          hash_including(missing_rx_number: true, missing_station_prefix: false)
        )
      end

      it 'logs a warning when station-prefix identifier is missing but rx-number is present' do
        resource = base_fhir_resource.merge(
          'id' => '20848999999',
          'identifier' => [
            { 'system' => 'http://va.gov/identifier/rx-number', 'value' => '12345678' }
          ]
        )
        allow(Rails.logger).to receive(:warn)

        result = subject.parse(resource)

        expect(result.prescription_number).to be_nil
        expect(Rails.logger).to have_received(:warn).with(
          'Oracle Health prescription missing identifier',
          hash_including(missing_rx_number: false, missing_station_prefix: true)
        )
      end

      it 'logs at debug level when both identifiers are missing' do
        resource = base_fhir_resource.merge(
          'id' => '20848999999',
          'identifier' => []
        )
        allow(Rails.logger).to receive(:debug)

        result = subject.parse(resource)

        expect(result.prescription_number).to be_nil
        expect(Rails.logger).to have_received(:debug).with(
          'Oracle Health prescription missing both identifiers',
          hash_including(missing_rx_number: true, missing_station_prefix: true)
        )
      end
    end

    context 'with completed dispense without tracking data logging' do
      it 'logs warning when completed dispenses exist without tracking data' do
        resource = fhir_resource(status: 'active', dispense_status: 'completed')
        resource['contained'] = [
          { 'resourceType' => 'MedicationDispense', 'id' => 'dispense-1',
            'status' => 'completed', 'whenHandedOver' => '2025-01-15T10:00:00Z' }
        ]

        expect(Rails.logger).to receive(:warn).with(
          hash_including(
            message: 'Completed dispenses without tracking data',
            service: 'unified_health_data'
          )
        )
        expect(StatsD).to receive(:increment)
          .with('unified_health_data.prescriptions.completed_dispense_without_tracking')

        subject.parse(resource)
      end

      it 'does not log when tracking data exists' do
        resource = fhir_resource(status: 'active', dispense_status: 'completed')
        resource['contained'] = [
          { 'resourceType' => 'MedicationDispense', 'id' => 'dispense-1',
            'status' => 'completed', 'whenHandedOver' => '2025-01-15T10:00:00Z',
            'extension' => [{
              'url' => 'http://va.gov/fhir/StructureDefinition/shipping-info',
              'extension' => [
                { 'url' => 'Tracking Number', 'valueString' => '9400111899223100000001' }
              ]
            }] }
        ]

        expect(Rails.logger).not_to receive(:warn).with(
          hash_including(message: 'Completed dispenses without tracking data')
        )

        subject.parse(resource)
      end

      it 'does not log when no completed dispenses exist' do
        resource = fhir_resource(status: 'active', dispense_status: 'in-progress')

        expect(Rails.logger).not_to receive(:warn).with(
          hash_including(message: 'Completed dispenses without tracking data')
        )

        subject.parse(resource)
      end
    end

    context 'with NDC code extraction' do
      it 'extracts NDC from medicationCodeableConcept coding' do
        resource = {
          'id' => '12345',
          'medicationCodeableConcept' => {
            'coding' => [
              { 'system' => 'http://hl7.org/fhir/sid/ndc', 'code' => '00487-9801-01' }
            ]
          },
          'contained' => []
        }

        result = subject.parse(resource)

        # NDC should be extracted even without tracking data
        expect(result).to be_a(UnifiedHealthData::Prescription)
        # NOTE: NDC is not directly exposed in Prescription model, but is used internally
        # Test via tracking if present, or verify it's extracted correctly in helper methods
      end

      it 'finds NDC in coding array with multiple systems' do
        resource = {
          'id' => '12345',
          'medicationCodeableConcept' => {
            'coding' => [
              { 'system' => 'http://example.com/other', 'code' => 'OTHER-123' },
              { 'system' => 'http://hl7.org/fhir/sid/ndc', 'code' => '12345-6789-01' },
              { 'system' => 'http://rxnorm.org', 'code' => 'RXNORM-456' }
            ]
          },
          'contained' => [
            {
              'resourceType' => 'MedicationDispense',
              'extension' => [
                {
                  'url' => 'http://va.gov/fhir/StructureDefinition/shipping-info',
                  'extension' => [
                    { 'url' => 'Tracking Number', 'valueString' => 'TRACK-001' }
                  ]
                }
              ]
            }
          ]
        }

        result = subject.parse(resource)

        expect(result).to be_a(UnifiedHealthData::Prescription)
        # Verify NDC was extracted correctly by checking tracking data
        tracking = result.tracking.first
        expect(tracking[:ndc_number]).to eq('12345-6789-01')
      end

      it 'falls back to dispense NDC when medicationCodeableConcept has no NDC' do
        resource = {
          'id' => '12345',
          'medicationCodeableConcept' => {
            'coding' => [
              { 'system' => 'http://rxnorm.org', 'code' => 'RXNORM-456' }
            ]
          },
          'contained' => [
            {
              'resourceType' => 'MedicationDispense',
              'whenHandedOver' => '2025-11-17T21:35:02.000Z',
              'medicationCodeableConcept' => {
                'coding' => [
                  { 'system' => 'http://hl7.org/fhir/sid/ndc', 'code' => '99999-8888-77' }
                ]
              },
              'extension' => [
                {
                  'url' => 'http://va.gov/fhir/StructureDefinition/shipping-info',
                  'extension' => [
                    { 'url' => 'Tracking Number', 'valueString' => 'TRACK-002' }
                  ]
                }
              ]
            }
          ]
        }

        result = subject.parse(resource)

        expect(result).to be_a(UnifiedHealthData::Prescription)
        tracking = result.tracking.first
        expect(tracking[:ndc_number]).to eq('99999-8888-77')
      end

      it 'returns nil when no NDC is available anywhere' do
        resource = {
          'id' => '12345',
          'medicationCodeableConcept' => {
            'text' => 'Some medication'
          },
          'contained' => []
        }

        result = subject.parse(resource)

        expect(result).to be_a(UnifiedHealthData::Prescription)
        # When no tracking data exists, tracking array should be empty
        expect(result.tracking).to be_empty
      end
    end

    context 'with legacy identifier-based tracking' do
      it 'builds tracking from MedicationDispense identifiers when no extension exists' do
        resource = base_fhir_resource.merge(
          'id' => '12345',
          'contained' => [
            {
              'resourceType' => 'MedicationDispense',
              'identifier' => [
                { 'type' => { 'text' => 'Tracking Number' }, 'value' => '77298027203980000000398' },
                { 'type' => { 'text' => 'Carrier' }, 'value' => 'UPS' }
              ],
              'medicationCodeableConcept' => {
                'coding' => [
                  { 'system' => 'http://hl7.org/fhir/sid/ndc', 'code' => '11111-2222-33' }
                ]
              }
            }
          ]
        )

        result = subject.parse(resource)

        expect(result.is_trackable).to be true
        expect(result.tracking.length).to eq(1)
        expect(result.tracking.first[:tracking_number]).to eq('77298027203980000000398')
        expect(result.tracking.first[:carrier]).to eq('UPS')
      end

      it 'sets is_trackable to false when no tracking exists' do
        result = subject.parse(base_fhir_resource)
        expect(result.is_trackable).to be false
      end
    end

    context 'with sorted_dispensed_date extraction' do
      it 'returns the most recent when_handed_over from dispenses' do
        resource = fhir_resource(
          dispense_date: '2025-07-20T10:00:00Z'
        )
        # Add a second dispense with an earlier date
        resource['contained'] << {
          'resourceType' => 'MedicationDispense',
          'id' => 'dispense-2',
          'status' => 'completed',
          'whenHandedOver' => '2025-07-10T08:00:00Z',
          'location' => { 'display' => '648' }
        }

        result = subject.parse(resource)
        expect(result.sorted_dispensed_date).to eq('2025-07-20')
      end

      it 'falls back to when_prepared when when_handed_over is absent' do
        resource = base_fhir_resource.merge(
          'contained' => [
            {
              'resourceType' => 'MedicationDispense',
              'id' => 'dispense-1',
              'status' => 'completed',
              'whenPrepared' => '2025-03-05T09:00:00Z',
              'location' => { 'display' => '648' }
            },
            {
              'resourceType' => 'MedicationDispense',
              'id' => 'dispense-2',
              'status' => 'completed',
              'whenPrepared' => '2025-03-01T10:00:00Z',
              'location' => { 'display' => '648' }
            }
          ]
        )

        result = subject.parse(resource)
        expect(result.sorted_dispensed_date).to eq('2025-03-05')
      end

      it 'returns nil when no dispenses exist' do
        result = subject.parse(base_fhir_resource)
        expect(result.sorted_dispensed_date).to be_nil
      end

      it 'ignores invalid dispense dates and uses the most recent valid date' do
        resource = base_fhir_resource.merge(
          'contained' => [
            {
              'resourceType' => 'MedicationDispense',
              'id' => 'dispense-invalid',
              'status' => 'completed',
              'whenHandedOver' => 'not-a-valid-datetime',
              'location' => { 'display' => '648' }
            },
            {
              'resourceType' => 'MedicationDispense',
              'id' => 'dispense-valid',
              'status' => 'completed',
              'whenHandedOver' => '2025-03-06T12:00:00Z',
              'location' => { 'display' => '648' }
            }
          ]
        )

        result = subject.parse(resource)
        expect(result.sorted_dispensed_date).to eq('2025-03-06')
      end
    end

    context 'with expiration date normalization' do
      it 'infers correct local date from Pacific offset UTC timestamp' do
        # Simulate Oracle Health: 23:59:59 PST Nov 16 = 07:59:59 UTC Nov 17
        resource = fhir_resource(expiration: Time.utc(2026, 11, 17, 7, 59, 59))
        result = subject.parse(resource)

        # Subtracting 12h from 07:59:59Z → Nov 16, noon UTC
        expect(result.expiration_date).to eq('2026-11-16T12:00:00.000Z')
      end

      it 'infers correct local date from Eastern offset UTC timestamp' do
        # 23:59:59 EST Nov 16 = 04:59:59 UTC Nov 17
        resource = fhir_resource(expiration: Time.utc(2026, 11, 17, 4, 59, 59))
        result = subject.parse(resource)

        expect(result.expiration_date).to eq('2026-11-16T12:00:00.000Z')
      end

      it 'infers correct local date from Guam offset UTC timestamp' do
        # 23:59:59 ChST(+10) Nov 16 = 13:59:59 UTC Nov 16 — same UTC date, still correct
        resource = fhir_resource(expiration: Time.utc(2026, 11, 16, 13, 59, 59))
        result = subject.parse(resource)

        expect(result.expiration_date).to eq('2026-11-16T12:00:00.000Z')
      end

      it 'does not warn when inferred date matches facility timezone' do
        facility_tz_service = instance_double(UnifiedHealthData::FacilityService)
        allow(UnifiedHealthData::FacilityService).to receive(:new).and_return(facility_tz_service)
        allow(facility_tz_service).to receive(:get_facility_timezone).and_return('America/Los_Angeles')

        resource = fhir_resource(expiration: Time.utc(2026, 11, 17, 7, 59, 59))

        expect(Rails.logger).not_to receive(:warn).with(
          hash_including(
            message: 'Expiration date mismatch between inferred and facility timezone'
          )
        )

        subject.parse(resource)
      end

      it 'logs a warning when inferred date differs from facility timezone date' do
        facility_tz_service = instance_double(UnifiedHealthData::FacilityService)
        allow(UnifiedHealthData::FacilityService).to receive(:new).and_return(facility_tz_service)
        # Facility says Guam (+10) but the timestamp is clearly Pacific (-8)
        allow(facility_tz_service).to receive(:get_facility_timezone).and_return('Pacific/Guam')

        # 07:59:59Z = 23:59:59 PST Nov 16. In Guam time, 07:59:59Z = Nov 17 17:59:59 → Nov 17.
        resource = fhir_resource(expiration: Time.utc(2026, 11, 17, 7, 59, 59))

        expect(Rails.logger).to receive(:warn).with(
          hash_including(
            message: 'Expiration date mismatch between inferred and facility timezone'
          )
        )

        result = subject.parse(resource)
        # Inference is always used as the return value
        expect(result.expiration_date).to eq('2026-11-16T12:00:00.000Z')
      end

      it 'returns nil when no expiration date exists' do
        resource = fhir_resource(status: 'active', refills: 5)
        resource['dispenseRequest'].delete('validityPeriod')

        result = subject.parse(resource)
        expect(result.expiration_date).to be_nil
      end
    end

    describe 'quantity formatting' do
      it 'removes trailing zeros from quantity' do
        resource = fhir_resource(source: 'VA')
        resource['dispenseRequest']['quantity'] = { 'value' => 60.0 }

        result = subject.parse(resource)
        expect(result.quantity).to eq('60')
      end

      it 'removes trailing zeros after decimal while preserving significant digits' do
        resource = fhir_resource(source: 'VA')
        resource['dispenseRequest']['quantity'] = { 'value' => 1.50 }

        result = subject.parse(resource)
        expect(result.quantity).to eq('1.5')
      end

      it 'preserves significant decimals' do
        resource = fhir_resource(source: 'VA')
        resource['dispenseRequest']['quantity'] = { 'value' => 2.25 }

        result = subject.parse(resource)
        expect(result.quantity).to eq('2.25')
      end

      it 'returns nil when quantity is not present' do
        resource = fhir_resource(source: 'VA')
        resource['dispenseRequest'].delete('quantity')
        resource['contained'] = []

        result = subject.parse(resource)
        expect(result.quantity).to be_nil
      end

      it 'returns unformatted string when BigDecimal conversion fails' do
        resource = fhir_resource(source: 'VA')
        resource['dispenseRequest']['quantity'] = { 'value' => 'invalid-quantity' }

        result = subject.parse(resource)
        expect(result.quantity).to eq('invalid-quantity')
      end
    end

    context 'with facility phone from shipping-info extension' do
      let(:resource_with_phone) do
        resource = fhir_resource(status: 'active', refills: 3, expiration: 1.year.from_now)
        resource['contained'] = [
          {
            'resourceType' => 'MedicationDispense',
            'id' => 'dispense-1',
            'status' => 'completed',
            'whenHandedOver' => '2025-01-15T10:00:00Z',
            'location' => { 'display' => '648' },
            'extension' => [
              {
                'url' => 'http://va.gov/fhir/StructureDefinition/shipping-info',
                'extension' => [
                  { 'url' => 'Facility Phone', 'valueString' => '(800) 784-8381' }
                ]
              }
            ]
          }
        ]
        resource
      end

      it 'populates facility_phone_number from extension' do
        result = subject.parse(resource_with_phone)
        expect(result.facility_phone_number).to eq('(800) 784-8381')
      end

      it 'populates cmop_division_phone from extension' do
        result = subject.parse(resource_with_phone)
        expect(result.cmop_division_phone).to eq('(800) 784-8381')
      end

      it 'populates dial_cmop_division_phone as digits only' do
        result = subject.parse(resource_with_phone)
        expect(result.dial_cmop_division_phone).to eq('8007848381')
      end
    end

    context 'without facility phone in extensions' do
      it 'sets phone fields to nil' do
        result = subject.parse(base_fhir_resource)
        expect(result.facility_phone_number).to be_nil
        expect(result.cmop_division_phone).to be_nil
        expect(result.dial_cmop_division_phone).to be_nil
      end
    end

    describe '#strip_phone_to_digits' do
      let(:adapter) { described_class.new }

      it 'strips formatting from a phone number' do
        expect(adapter.send(:strip_phone_to_digits, '(800) 784-8381')).to eq('8007848381')
      end

      it 'truncates at extension characters' do
        expect(adapter.send(:strip_phone_to_digits, '(800) 784-8381 x1234')).to eq('8007848381')
        expect(adapter.send(:strip_phone_to_digits, '800-784-8381#5')).to eq('8007848381')
      end

      it 'returns nil for blank input' do
        expect(adapter.send(:strip_phone_to_digits, nil)).to be_nil
        expect(adapter.send(:strip_phone_to_digits, '')).to be_nil
      end

      it 'handles digits-only input' do
        expect(adapter.send(:strip_phone_to_digits, '8007848381')).to eq('8007848381')
      end
    end

    context 'is_renewal_flow_enabled when facility cannot be resolved' do
      before do
        allow(HealthFacility).to receive(:find_by).and_return(nil)
        allow_any_instance_of(Lighthouse::Facilities::V1::Client).to receive(:get_facilities).and_return([])
      end

      it 'returns false even when medication is renewable' do
        resource = fhir_resource(status: 'active', refills: 0, expiration: 30.days.from_now)
        result = subject.parse(resource)
        expect(result.is_renewal_flow_enabled).to be false
      end
    end
  end
end
