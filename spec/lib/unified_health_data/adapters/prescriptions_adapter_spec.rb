# frozen_string_literal: true

require 'rails_helper'
require 'unified_health_data/models/prescription'
require 'unified_health_data/adapters/prescriptions_adapter'
require 'unified_health_data/facility_service'

describe UnifiedHealthData::Adapters::PrescriptionsAdapter do
  include ActiveSupport::Testing::TimeHelpers

  subject { described_class.new(user) }

  let(:user) { build(:user, :loa3, icn: '1000123456V123456') }
  let(:vista_medication_data) do
    {
      'prescriptionId' => '28148665',
      'refillStatus' => 'active',
      'refillSubmitDate' => nil,
      'refillDate' => 'Mon, 14 Jul 2025 00:00:00 EDT',
      'refillRemaining' => 11,
      'facilityName' => 'SLC4',
      'isRefillable' => true,
      'isTrackable' => false,
      'sig' => 'APPLY TEASPOONFUL(S) TO THE AFFECTED AREA EVERY DAY',
      'orderedDate' => 'Mon, 14 Jul 2025 00:00:00 EDT',
      'quantity' => 1,
      'expirationDate' => 'Wed, 15 Jul 2026 00:00:00 EDT',
      'prescriptionNumber' => '3636485',
      'prescriptionName' => 'COAL TAR 2.5% TOP SOLN',
      'dispensedDate' => nil,
      'stationNumber' => '991',
      'cmopDivisionPhone' => '555-1234',
      'providerLastName' => 'SMITH',
      'providerFirstName' => 'JOHN',
      'dialCmopDivisionPhone' => '555-DIAL',
      'remarks' => 'TEST REMARKS FOR VISTA',
      'cmopNdcNumber' => '00093721410',
      'dataSourceSystem' => 'VISTA'
    }
  end
  let(:oracle_health_medication_data) do
    {
      'resourceType' => 'MedicationRequest',
      'id' => '15208365735',
      'status' => 'active',
      'authoredOn' => '2025-01-29T19:41:43Z',
      'reportedBoolean' => false,
      'intent' => 'order',
      'category' => [
        {
          'coding' => [
            { 'system' => 'http://terminology.hl7.org/CodeSystem/medicationrequest-admin-location', 'code' => 'community' }
          ]
        },
        {
          'coding' => [
            { 'system' => 'http://terminology.hl7.org/CodeSystem/medication-request-category', 'code' => 'discharge' }
          ]
        }
      ],
      'requester' => {
        'reference' => 'Practitioner/12345',
        'display' => 'Doe, Jane, MD'
      },
      'medicationCodeableConcept' => {
        'text' => 'amLODIPine (amLODIPine 5 mg tablet)'
      },
      'dosageInstruction' => [
        {
          'text' => 'See Instructions, daily, 1 EA, 0 Refill(s)'
        }
      ],
      'dispenseRequest' => {
        'numberOfRepeatsAllowed' => 0,
        'quantity' => {
          'value' => 1,
          'unit' => 'EA'
        }
      },
      'note' => [
        { 'text' => 'Take with food.' },
        { 'text' => 'May cause dizziness.' }
      ],
      'contained' => [
        {
          'resourceType' => 'MedicationDispense',
          'id' => 'dispense-1',
          'whenHandedOver' => '2025-01-15T10:00:00Z',
          'quantity' => { 'value' => 30 },
          'location' => { 'display' => 'Main Pharmacy' }
        },
        {
          'resourceType' => 'MedicationDispense',
          'id' => 'dispense-2',
          'whenHandedOver' => '2025-01-29T14:30:00Z',
          'quantity' => { 'value' => 30 },
          'location' => { 'display' => 'Main Pharmacy' }
        },
        {
          'resourceType' => 'MedicationDispense',
          'id' => 'dispense-3',
          'whenHandedOver' => '2025-01-22T09:15:00Z',
          'quantity' => { 'value' => 30 },
          'location' => { 'display' => 'Main Pharmacy' }
        }
      ]
    }
  end
  let(:unified_response) do
    {
      'vista' => {
        'medicationList' => {
          'medication' => [vista_medication_data]
        }
      },
      'oracle-health' => {
        'entry' => [
          {
            'resource' => oracle_health_medication_data
          }
        ]
      }
    }
  end

  before do
    allow(Rails.cache).to receive(:exist?).and_return(false)

    # Stub facility timezone service for OH expiration date normalization
    facility_tz_service = instance_double(UnifiedHealthData::FacilityService)
    allow(UnifiedHealthData::FacilityService).to receive(:new).and_return(facility_tz_service)
    allow(facility_tz_service).to receive(:get_facility_timezone) do |station_number|
      expect(station_number).to match(/^\d{3}$/)
      'America/Los_Angeles'
    end

    # Stub HealthFacility for facility name resolution
    facility = instance_double(HealthFacility, name: 'Portland VA Medical Center')
    allow(HealthFacility).to receive(:find_by).and_return(facility)
  end

  describe '#parse' do
    context 'with unified response data' do
      before do
        # Ensure business rules filtering doesn't interfere with basic parsing tests
        allow(Flipper).to receive(:enabled?).with(:mhv_medications_display_pending_meds, user).and_return(false)
        allow(Flipper).to receive(:enabled?).with(:mhv_medications_management_improvements, user).and_return(false)
      end

      it 'returns prescriptions from both VistA and Oracle Health' do
        prescriptions = subject.parse(unified_response)[:prescriptions]

        expect(prescriptions.size).to eq(2)
        expect(prescriptions).to all(be_a(UnifiedHealthData::Prescription))

        vista_prescription = prescriptions.find { |p| p.prescription_id == '28148665' }
        oracle_prescription = prescriptions.find { |p| p.prescription_id == '15208365735' }

        expect(vista_prescription).to be_present
        expect(oracle_prescription).to be_present
      end

      it 'extracts provider_name from VistA data' do
        prescriptions = subject.parse(unified_response)[:prescriptions]
        vista_prescription = prescriptions.find { |p| p.prescription_id == '28148665' }

        expect(vista_prescription.provider_name).to eq('SMITH, JOHN')
      end

      it 'extracts provider_name from Oracle Health data' do
        prescriptions = subject.parse(unified_response)[:prescriptions]
        oracle_prescription = prescriptions.find { |p| p.prescription_id == '15208365735' }

        expect(oracle_prescription.provider_name).to eq('Doe, Jane, MD')
      end

      it 'sets cmop_division_phone correctly for both sources' do
        prescriptions = subject.parse(unified_response)[:prescriptions]

        vista_prescription = prescriptions.find { |p| p.prescription_id == '28148665' }
        oracle_prescription = prescriptions.find { |p| p.prescription_id == '15208365735' }

        expect(vista_prescription.cmop_division_phone).to eq('555-1234')
        expect(oracle_prescription.cmop_division_phone).to be_nil
      end

      it 'sets cmop_ndc_number from VistA source and null for Oracle Health source' do
        prescriptions = subject.parse(unified_response)[:prescriptions]

        vista_prescription = prescriptions.find { |p| p.prescription_id == '28148665' }
        oracle_prescription = prescriptions.find { |p| p.prescription_id == '15208365735' }

        expect(vista_prescription.cmop_ndc_number).to eq('00093721410')
        expect(oracle_prescription.cmop_ndc_number).to be_nil
      end

      it 'extracts disp_status from VistA data when present' do
        # disp_status should be preserved as-is from VistA
        vista_data_with_disp_status = vista_medication_data.merge('dispStatus' => 'Active: Refill in Process')
        response_with_disp_status = {
          'vista' => { 'medicationList' => { 'medication' => [vista_data_with_disp_status] } },
          'oracle-health' => { 'entry' => [] }
        }

        prescriptions = subject.parse(response_with_disp_status)[:prescriptions]
        vista_prescription = prescriptions.first

        expect(vista_prescription.disp_status).to eq('Active: Refill in Process')
      end

      it 'sets disp_status derived from refill_status for Oracle Health prescriptions' do
        # disp_status is derived from refill_status only when dispStatus is not already set
        prescriptions = subject.parse(unified_response)[:prescriptions]
        oracle_prescription = prescriptions.find { |p| p.prescription_id == '15208365735' }

        # Oracle Health prescription with status='active', 0 refills remaining, no expiration date
        # = 'active' refill_status which maps to 'Active' disp_status
        # (derived from refill_status when dispStatus is null)
        expect(oracle_prescription.disp_status).to eq('Active')
      end

      context 'business rules filtering (applied regardless of current_only)' do
        context 'when display_pending_meds flipper is enabled' do
          let(:vista_medication_pf) do
            vista_medication_data.merge('prescriptionSource' => 'PF')
          end

          let(:vista_medication_pd) do
            vista_medication_data.merge('prescriptionSource' => 'PD')
          end

          let(:response_with_pf) do
            {
              'vista' => { 'medicationList' => { 'medication' => [vista_medication_pf] } },
              'oracle-health' => { 'entry' => [] }
            }
          end

          let(:response_with_pd) do
            {
              'vista' => { 'medicationList' => { 'medication' => [vista_medication_pd] } },
              'oracle-health' => { 'entry' => [] }
            }
          end

          before do
            allow(Flipper).to receive(:enabled?).with(:mhv_medications_display_pending_meds, user).and_return(true)
          end

          it 'excludes PF (Partial Fill) prescriptions only' do
            prescriptions = subject.parse(response_with_pf)[:prescriptions]
            expect(prescriptions).to be_empty
          end

          it 'includes PD (Pending) prescriptions when flag is enabled' do
            prescriptions = subject.parse(response_with_pd)[:prescriptions]
            expect(prescriptions.size).to eq(1)
            expect(prescriptions.first.prescription_source).to eq('PD')
          end
        end

        context 'when display_pending_meds flipper is disabled' do
          let(:vista_medication_pf) do
            vista_medication_data.merge('prescriptionSource' => 'PF')
          end

          let(:vista_medication_pd) do
            vista_medication_data.merge('prescriptionSource' => 'PD')
          end

          let(:response_with_pf_and_pd) do
            {
              'vista' => { 'medicationList' => { 'medication' => [vista_medication_pf, vista_medication_pd] } },
              'oracle-health' => { 'entry' => [] }
            }
          end

          before do
            allow(Flipper).to receive(:enabled?).with(:mhv_medications_display_pending_meds, user).and_return(false)
          end

          it 'excludes both PF and PD prescriptions' do
            prescriptions = subject.parse(response_with_pf_and_pd)[:prescriptions]
            expect(prescriptions).to be_empty
          end
        end
      end

      context 'with current_only: false (default)' do
        it 'returns all prescriptions without filtering' do
          prescriptions = subject.parse(unified_response, current_only: false)[:prescriptions]

          expect(prescriptions.size).to eq(2)
          expect(prescriptions).to all(be_a(UnifiedHealthData::Prescription))
        end
      end

      context 'with current_only: true' do
        let(:vista_medication_expired_old) do
          vista_medication_data.merge(
            'refillStatus' => 'expired',
            'expirationDate' => 200.days.ago.strftime('%a, %d %b %Y %H:%M:%S %Z')
          )
        end

        context 'filters out old discontinued/expired prescriptions' do
          let(:response_with_old_expired) do
            {
              'vista' => { 'medicationList' => { 'medication' => [vista_medication_expired_old] } },
              'oracle-health' => { 'entry' => [] }
            }
          end

          it 'excludes expired prescriptions older than 180 days' do
            allow(Rails.logger).to receive(:info)

            prescriptions = subject.parse(response_with_old_expired, current_only: true)[:prescriptions]

            expect(prescriptions).to be_empty
            expect(Rails.logger).to have_received(:info).with(
              hash_including(
                message: 'Applied current filtering to prescriptions',
                excluded_count: 1
              )
            )
          end
        end

        context 'handles invalid expiration dates gracefully' do
          let(:vista_medication_invalid_date) do
            vista_medication_data.merge(
              'refillStatus' => 'expired',
              'expirationDate' => 'invalid-date'
            )
          end

          let(:response_with_invalid_date) do
            {
              'vista' => { 'medicationList' => { 'medication' => [vista_medication_invalid_date] } },
              'oracle-health' => { 'entry' => [] }
            }
          end

          it 'logs warning from adapter and does not exclude based on date' do
            allow(Rails.logger).to receive(:warn)
            allow(Rails.logger).to receive(:info)

            prescriptions = subject.parse(response_with_invalid_date, current_only: true)[:prescriptions]

            expect(prescriptions.size).to eq(1)
            # The VistA adapter logs the warning during normalization
            expect(Rails.logger).to have_received(:warn).with(
              /Failed to normalize expiration date 'invalid-date'/
            )
          end
        end

        context 'does not filter active or recent prescriptions' do
          it 'includes active prescriptions regardless of expiration date' do
            allow(Rails.logger).to receive(:info)

            prescriptions = subject.parse(unified_response, current_only: true)[:prescriptions]

            expect(prescriptions.size).to eq(2)
            expect(Rails.logger).to have_received(:info).with(
              hash_including(
                message: 'Applied current filtering to prescriptions',
                original_count: 2,
                filtered_count: 2,
                excluded_count: 0
              )
            )
          end
        end

        # Boundary + discontinued side of prescription_not_current?.
        # Time is frozen at noon UTC so that Date.parse (which truncates the noon-UTC-normalized
        # expiration to midnight) compares deterministically against `180.days.ago`.
        context 'boundary and discontinued side of the 180-day rule' do
          around do |example|
            travel_to(Time.zone.parse('2025-06-26T12:00:00Z')) { example.run }
          end

          def vista_med(refill_status:, days_ago:)
            vista_medication_data.merge(
              'refillStatus' => refill_status,
              'expirationDate' => days_ago.days.ago.strftime('%a, %d %b %Y %H:%M:%S %Z')
            )
          end

          def response_for(med)
            { 'vista' => { 'medicationList' => { 'medication' => [med] } },
              'oracle-health' => { 'entry' => [] } }
          end

          before { allow(Rails.logger).to receive(:info) }

          it 'excludes a DISCONTINUED med older than 180 days' do
            prescriptions = subject.parse(response_for(vista_med(refill_status: 'discontinued', days_ago: 200)),
                                          current_only: true)[:prescriptions]
            expect(prescriptions).to be_empty
          end

          it 'keeps a DISCONTINUED med comfortably inside the 180-day window' do
            prescriptions = subject.parse(response_for(vista_med(refill_status: 'discontinued', days_ago: 100)),
                                          current_only: true)[:prescriptions]
            expect(prescriptions.size).to eq(1)
          end

          it 'excludes a discontinued med whose expiration date equals the 180-day mark (comparator is strict <)' do
            # The noon-UTC expiration truncates to midnight, which is < 180.days.ago (frozen at noon).
            prescriptions = subject.parse(response_for(vista_med(refill_status: 'discontinued', days_ago: 180)),
                                          current_only: true)[:prescriptions]
            expect(prescriptions).to be_empty
          end

          it 'keeps a discontinued med one day inside the 180-day mark' do
            prescriptions = subject.parse(response_for(vista_med(refill_status: 'discontinued', days_ago: 179)),
                                          current_only: true)[:prescriptions]
            expect(prescriptions.size).to eq(1)
          end
        end
      end
    end

    context 'with VistA-only data' do
      let(:vista_only_response) do
        {
          'vista' => unified_response['vista'],
          'oracle-health' => nil
        }
      end

      it 'returns only VistA prescriptions' do
        prescriptions = subject.parse(vista_only_response)[:prescriptions]

        expect(prescriptions.size).to eq(1)
        expect(prescriptions.first.prescription_id).to eq('28148665')
        expect(prescriptions.first.prescription_name).to eq('COAL TAR 2.5% TOP SOLN')
      end

      it 'falls back to orderableItem when prescriptionName is missing' do
        vista_data_without_name = vista_medication_data.merge(
          'prescriptionName' => nil,
          'orderableItem' => 'METFORMIN 500MG TABLET'
        )
        response = {
          'vista' => { 'medicationList' => { 'medication' => [vista_data_without_name] } },
          'oracle-health' => nil
        }

        prescriptions = subject.parse(response)[:prescriptions]

        expect(prescriptions.size).to eq(1)
        expect(prescriptions.first.prescription_name).to eq('METFORMIN 500MG TABLET')
      end
    end

    context 'with VistA prescriptions at Oracle Health stations' do
      subject(:parsed) { described_class.new(user).parse(response)[:prescriptions] }

      let(:oh_stations) { '668, 528GQ01' }
      let(:enforced) { true }
      let(:vista_medications) { [vista_medication_data.merge('stationNumber' => '668')] }
      let(:response) do
        {
          'vista' => { 'medicationList' => { 'medication' => vista_medications } },
          'oracle-health' => nil
        }
      end

      before do
        allow(Settings.mhv.oh_facility_checks).to receive(:vista_suppression_oh_stations).and_return(oh_stations)
        allow(Flipper).to receive(:enabled?).and_return(false)
        allow(Flipper).to receive(:enabled?)
          .with(:mhv_medications_suppress_vista_rx_at_oh_stations, user).and_return(enforced)
        allow(StatsD).to receive(:increment)
        allow(StatsD).to receive(:gauge)
        allow(Rails.logger).to receive(:info)
      end

      context 'when the flag is enabled' do
        it 'suppresses both is_refillable and is_renewable' do
          rx = parsed.first

          expect(rx.is_refillable).to be(false)
          expect(rx.is_renewable).to be(false)
        end

        it 'leaves the prescription in the list with its display status untouched' do
          rx = parsed.first

          expect(parsed.size).to eq(1)
          expect(rx.prescription_id).to eq('28148665')
          expect(rx.refill_status).to eq('active')
        end

        context 'when the prescription was refillable but not renewable' do
          let(:vista_medications) do
            [vista_medication_data.merge('stationNumber' => '668', 'isRefillable' => true,
                                         'dispStatus' => 'Active', 'refillRemaining' => 5)]
          end

          it 'flips the true flag and leaves the already-false flag false' do
            rx = parsed.first

            expect(rx.is_refillable).to be(false)
            expect(rx.is_renewable).to be(false)
          end
        end

        context 'when the prescription was renewable but not refillable' do
          let(:vista_medications) do
            [vista_medication_data.merge('stationNumber' => '668', 'isRefillable' => false,
                                         'dispStatus' => 'Active', 'refillRemaining' => 0)]
          end

          it 'flips the true flag and leaves the already-false flag false' do
            rx = parsed.first

            expect(rx.is_refillable).to be(false)
            expect(rx.is_renewable).to be(false)
          end
        end

        context 'when a child station is listed explicitly' do
          let(:vista_medications) { [vista_medication_data.merge('stationNumber' => '528GQ01')] }

          it 'suppresses on the exact match' do
            expect(parsed.first.is_refillable).to be(false)
          end
        end

        context 'when only the parent station is listed' do
          let(:vista_medications) { [vista_medication_data.merge('stationNumber' => '668A4')] }

          it 'does not suppress the child station' do
            expect(parsed.first.is_refillable).to be(true)
          end
        end

        context 'when the station number carries surrounding whitespace' do
          let(:vista_medications) { [vista_medication_data.merge('stationNumber' => ' 668 ')] }

          it 'still matches' do
            expect(parsed.first.is_refillable).to be(false)
          end
        end

        context 'when the child station casing differs from the setting' do
          let(:oh_stations) { '528gq01' }
          let(:vista_medications) { [vista_medication_data.merge('stationNumber' => '528GQ01')] }

          it 'matches case-insensitively' do
            expect(parsed.first.is_refillable).to be(false)
          end
        end

        context 'when the station is not on Oracle Health' do
          let(:vista_medications) { [vista_medication_data.merge('stationNumber' => '991')] }

          it 'leaves the prescription untouched' do
            expect(parsed.first.is_refillable).to be(true)
          end

          it 'does not count the fetch' do
            parsed
            expect(StatsD).not_to have_received(:increment)
              .with(described_class::STATSD_SUPPRESSED_FETCHES, anything)
          end
        end

        context 'when the prescription is sourced from Oracle Health' do
          let(:response) do
            {
              'vista' => nil,
              'oracle-health' => unified_response['oracle-health']
            }
          end

          it 'leaves the prescription untouched' do
            expect(parsed.first.source_ehr).to eq(UnifiedHealthData::Prescription::SOURCE_EHR_ORACLE_HEALTH)
            expect(StatsD).not_to have_received(:increment)
              .with(described_class::STATSD_SUPPRESSED_FETCHES, anything)
          end
        end

        context 'when the station number is blank' do
          let(:vista_medications) { [vista_medication_data.merge('stationNumber' => nil)] }

          it 'leaves the prescription untouched without raising' do
            expect(parsed.first.is_refillable).to be(true)
          end
        end

        context 'when the prescription already offered neither affordance' do
          let(:vista_medications) do
            [vista_medication_data.merge('stationNumber' => '668', 'isRefillable' => false,
                                         'dispStatus' => 'Discontinued', 'refillRemaining' => 0)]
          end

          it 'leaves both flags false' do
            rx = parsed.first

            expect(rx.is_refillable).to be(false)
            expect(rx.is_renewable).to be(false)
          end

          it 'does not count a record with nothing to withdraw' do
            parsed

            expect(StatsD).not_to have_received(:increment)
              .with(described_class::STATSD_SUPPRESSED_FETCHES, anything)
          end

          it 'logs no breakdown line' do
            parsed

            expect(Rails.logger).not_to have_received(:info).with(
              hash_including(message: 'VistA prescription affordances suppressed at Oracle Health stations')
            )
          end
        end
      end

      context 'when the flag is disabled' do
        let(:enforced) { false }

        it 'leaves both flags unchanged' do
          rx = parsed.first

          expect(rx.is_refillable).to be(true)
          expect(rx.is_renewable).to be(false)
        end

        it 'emits no metrics' do
          parsed

          expect(StatsD).not_to have_received(:increment)
            .with(described_class::STATSD_SUPPRESSED_FETCHES, anything)
          expect(StatsD).not_to have_received(:gauge)
            .with(described_class::STATSD_CONFIGURED_STATIONS, anything)
        end
      end

      context 'when the flag is enabled and a prescription is suppressed' do
        it 'counts the fetch once, tagged by station only' do
          parsed

          expect(StatsD).to have_received(:increment)
            .with(described_class::STATSD_SUPPRESSED_FETCHES, tags: ['station_number:668']).once
        end

        it 'logs one breakdown line per fetch with the affordance and display status' do
          parsed

          expect(Rails.logger).to have_received(:info).with(
            hash_including(
              message: 'VistA prescription affordances suppressed at Oracle Health stations',
              suppressed_count: 1,
              by_station: { '668' => 1 },
              by_affordance: { 'refill' => 1 },
              by_disp_status: { 'none' => 1 }
            )
          )
        end

        context 'when both affordances were offered' do
          let(:vista_medications) do
            [vista_medication_data.merge('stationNumber' => '668', 'isRefillable' => true,
                                         'dispStatus' => 'Active', 'refillRemaining' => 0)]
          end

          it 'reports the affordance as both alongside the upstream display status' do
            parsed

            expect(Rails.logger).to have_received(:info).with(
              hash_including(by_affordance: { 'both' => 1 }, by_disp_status: { 'Active' => 1 })
            )
          end
        end

        context 'when several prescriptions are suppressed' do
          let(:vista_medications) do
            [
              vista_medication_data.merge('stationNumber' => '668', 'dispStatus' => 'Active'),
              vista_medication_data.merge('prescriptionId' => '28148666', 'stationNumber' => '528GQ01',
                                          'dispStatus' => 'Active')
            ]
          end

          it 'rolls them into a single log line' do
            parsed

            expect(Rails.logger).to have_received(:info).with(
              hash_including(
                suppressed_count: 2,
                by_station: { '668' => 1, '528GQ01' => 1 },
                by_disp_status: { 'Active' => 2 }
              )
            ).once
          end

          it 'counts the fetch once per station it touched' do
            parsed

            expect(StatsD).to have_received(:increment)
              .with(described_class::STATSD_SUPPRESSED_FETCHES, tags: ['station_number:668']).once
            expect(StatsD).to have_received(:increment)
              .with(described_class::STATSD_SUPPRESSED_FETCHES, tags: ['station_number:528GQ01']).once
          end
        end

        context 'when several prescriptions at the same station are suppressed' do
          let(:vista_medications) do
            [
              vista_medication_data.merge('stationNumber' => '668', 'dispStatus' => 'Active'),
              vista_medication_data.merge('prescriptionId' => '28148666', 'stationNumber' => '668',
                                          'dispStatus' => 'Active')
            ]
          end

          it 'counts the fetch once rather than once per record' do
            parsed

            expect(StatsD).to have_received(:increment)
              .with(described_class::STATSD_SUPPRESSED_FETCHES, tags: ['station_number:668']).once
          end

          it 'still reports every affected record in the log' do
            parsed

            expect(Rails.logger).to have_received(:info).with(
              hash_including(suppressed_count: 2, by_station: { '668' => 2 })
            )
          end
        end
      end

      context 'when no stations are configured' do
        let(:oh_stations) { '' }

        it 'fails open and leaves both flags unchanged' do
          rx = parsed.first

          expect(rx.is_refillable).to be(true)
          expect(rx.is_renewable).to be(false)
        end

        it 'emits no detection metric' do
          parsed

          expect(StatsD).not_to have_received(:increment)
            .with(described_class::STATSD_SUPPRESSED_FETCHES, anything)
        end

        it 'gauges the configured station count so a stale list is visible' do
          parsed

          expect(StatsD).to have_received(:gauge).with(described_class::STATSD_CONFIGURED_STATIONS, 0)
        end
      end

      context 'when the setting arrives from Parameter Store as an integer' do
        let(:oh_stations) { 668 }

        it 'still matches the station' do
          expect(parsed.first.is_refillable).to be(false)
        end
      end

      context 'when the setting was typed into Parameter Store with quotes' do
        let(:oh_stations) { '"668", "991"' }

        it 'still matches the station' do
          expect(parsed.first.is_refillable).to be(false)
        end
      end
    end

    context 'with Oracle Health-only data' do
      let(:oracle_only_response) do
        {
          'vista' => nil,
          'oracle-health' => unified_response['oracle-health']
        }
      end

      it 'returns only Oracle Health prescriptions' do
        prescriptions = subject.parse(oracle_only_response)[:prescriptions]

        expect(prescriptions.size).to eq(1)
        expect(prescriptions.first.prescription_id).to eq('15208365735')
        expect(prescriptions.first.prescription_name).to eq('amLODIPine (amLODIPine 5 mg tablet)')
      end
    end

    context 'with nil input' do
      it 'raises an ArgumentError' do
        expect { subject.parse(nil) }.to raise_error(ArgumentError, 'UHD returned an empty response body')
      end
    end

    context 'with empty data' do
      let(:empty_response) do
        {
          'vista' => { 'medicationList' => { 'medication' => [] } },
          'oracle-health' => { 'entry' => [] }
        }
      end

      it 'returns empty prescriptions' do
        expect(subject.parse(empty_response)[:prescriptions]).to eq([])
      end
    end

    context 'with Oracle Health data containing multiple MedicationDispense resources' do
      it 'uses the most recent dispensed date based on whenHandedOver' do
        prescriptions = subject.parse(unified_response)[:prescriptions]
        oracle_prescription = prescriptions.find { |p| p.prescription_id == '15208365735' }

        # Should use the most recent whenHandedOver date: '2025-01-29T14:30:00Z'
        expect(oracle_prescription.refill_date).to eq('2025-01-29T14:30:00Z')
      end
    end

    context 'with Oracle Health data containing dispense location' do
      let(:oracle_medication_with_dispense) do
        {
          'resourceType' => 'MedicationRequest',
          'id' => '15208365735',
          'status' => 'active',
          'authoredOn' => '2025-01-29T19:41:43Z',
          'medicationCodeableConcept' => {
            'text' => 'amLODIPine (amLODIPine 5 mg tablet)'
          },
          'contained' => [
            {
              'resourceType' => 'MedicationDispense',
              'id' => 'dispense-1',
              'status' => 'completed',
              'whenHandedOver' => '2025-01-29T14:30:00Z',
              'location' => {
                'display' => '648-PHARMACY-MAIN'
              }
            }
          ]
        }
      end

      let(:response_with_dispense) do
        {
          'vista' => nil,
          'oracle-health' => {
            'entry' => [
              {
                'resource' => oracle_medication_with_dispense
              }
            ]
          }
        }
      end

      before do
        # Mock Rails cache to return a facility name for station 648
        allow(Rails.cache).to receive(:read).with('uhd:facility_names:648').and_return('Portland VA Medical Center')
        allow(Rails.cache).to receive(:exist?).with('uhd:facility_names:648').and_return(true)
        allow(StatsD).to receive(:increment)
      end

      it 'extracts facility name from dispense location via cache' do
        prescriptions = subject.parse(response_with_dispense)[:prescriptions]
        oracle_prescription = prescriptions.first

        expect(oracle_prescription.facility_name).to eq('Portland VA Medical Center')
      end
    end

    context 'with Oracle Health inpatient prescriptions' do
      let(:oracle_medication_inpatient) do
        oracle_health_medication_data.merge(
          'category' => [
            {
              'coding' => [
                {
                  'system' => 'http://terminology.hl7.org/CodeSystem/medicationrequest-admin-location',
                  'code' => 'inpatient'
                }
              ]
            }
          ]
        )
      end

      let(:response_with_inpatient) do
        {
          'vista' => nil,
          'oracle-health' => {
            'entry' => [
              {
                'resource' => oracle_medication_inpatient
              }
            ]
          }
        }
      end

      it 'excludes inpatient prescriptions' do
        prescriptions = subject.parse(response_with_inpatient)[:prescriptions]
        expect(prescriptions).to be_empty
      end
    end

    context 'with Oracle Health outpatient prescriptions' do
      let(:oracle_medication_outpatient) do
        oracle_health_medication_data.merge(
          'category' => [
            {
              'coding' => [
                {
                  'system' => 'http://terminology.hl7.org/CodeSystem/medicationrequest-admin-location',
                  'code' => 'outpatient'
                }
              ]
            }
          ]
        )
      end

      let(:response_with_outpatient) do
        {
          'vista' => nil,
          'oracle-health' => {
            'entry' => [
              {
                'resource' => oracle_medication_outpatient
              }
            ]
          }
        }
      end

      it 'excludes clinic-administered outpatient prescriptions' do
        prescriptions = subject.parse(response_with_outpatient)[:prescriptions]
        expect(prescriptions).to be_empty
      end
    end

    context 'with Oracle Health community prescriptions' do
      let(:oracle_medication_community) do
        oracle_health_medication_data.merge(
          'category' => [
            {
              'coding' => [
                {
                  'system' => 'http://terminology.hl7.org/CodeSystem/medicationrequest-admin-location',
                  'code' => 'community'
                }
              ]
            }
          ]
        )
      end

      let(:response_with_community) do
        {
          'vista' => nil,
          'oracle-health' => {
            'entry' => [
              {
                'resource' => oracle_medication_community
              }
            ]
          }
        }
      end

      it 'includes community prescriptions' do
        prescriptions = subject.parse(response_with_community)[:prescriptions]
        expect(prescriptions.size).to eq(1)
        expect(prescriptions.first.category).to eq(['community'])
      end
    end

    context 'with Oracle Health prescriptions with multiple categories' do
      let(:oracle_medication_multiple_categories) do
        oracle_health_medication_data.merge(
          'category' => [
            {
              'coding' => [
                {
                  'system' => 'http://terminology.hl7.org/CodeSystem/medicationrequest-admin-location',
                  'code' => 'outpatient'
                }
              ]
            },
            {
              'coding' => [
                {
                  'system' => 'http://terminology.hl7.org/CodeSystem/medicationrequest-admin-location',
                  'code' => 'community'
                }
              ]
            }
          ]
        )
      end

      let(:response_with_multiple_categories) do
        {
          'vista' => nil,
          'oracle-health' => {
            'entry' => [
              {
                'resource' => oracle_medication_multiple_categories
              }
            ]
          }
        }
      end

      it 'includes prescriptions with multiple categories' do
        prescriptions = subject.parse(response_with_multiple_categories)[:prescriptions]
        expect(prescriptions.size).to eq(1)
        expect(prescriptions.first.category).to eq(%w[community outpatient])
      end
    end

    context 'with Oracle Health prescriptions with inpatient in multiple categories' do
      let(:oracle_medication_inpatient_and_community) do
        oracle_health_medication_data.merge(
          'category' => [
            {
              'coding' => [
                {
                  'system' => 'http://terminology.hl7.org/CodeSystem/medicationrequest-admin-location',
                  'code' => 'inpatient'
                }
              ]
            },
            {
              'coding' => [
                {
                  'system' => 'http://terminology.hl7.org/CodeSystem/medicationrequest-admin-location',
                  'code' => 'community'
                }
              ]
            }
          ]
        )
      end

      let(:response_with_inpatient_and_community) do
        {
          'vista' => nil,
          'oracle-health' => {
            'entry' => [
              {
                'resource' => oracle_medication_inpatient_and_community
              }
            ]
          }
        }
      end

      it 'excludes prescriptions if any category is inpatient' do
        prescriptions = subject.parse(response_with_inpatient_and_community)[:prescriptions]
        expect(prescriptions).to be_empty
      end
    end

    context 'with Vista prescriptions containing dispenses' do
      let(:vista_medication_with_dispenses) do
        vista_medication_data.merge(
          'rxRFRecords' => {
            'rfRecord' => [
              {
                'id' => 'rf-1',
                'refillStatus' => 'dispensed',
                'refillDate' => 'Mon, 14 Jul 2025 00:00:00 EDT',
                'refillSubmitDate' => 'Sun, 13 Jul 2025 00:00:00 EDT',
                'facilityName' => 'SLC4',
                'sig' => 'APPLY TEASPOONFUL(S) TO THE AFFECTED AREA EVERY DAY',
                'quantity' => 1,
                'prescriptionName' => 'COAL TAR 2.5% TOP SOLN',
                'prescriptionNumber' => 'RX001',
                'cmopDivisionPhone' => '800-555-0100',
                'cmopNdcNumber' => '12345-678-90',
                'remarks' => 'Handle with care',
                'dialCmopDivisionPhone' => '8005550100',
                'disclaimer' => 'This is a test disclaimer'
              },
              {
                'id' => 'rf-2',
                'refillStatus' => 'dispensed',
                'refillDate' => 'Tue, 15 Jul 2025 00:00:00 EDT',
                'facilityName' => 'SLC4',
                'sig' => 'APPLY TEASPOONFUL(S) TO THE AFFECTED AREA EVERY DAY',
                'quantity' => 1,
                'prescriptionName' => 'COAL TAR 2.5% TOP SOLN'
              }
            ]
          }
        )
      end

      let(:response_with_vista_dispenses) do
        {
          'vista' => {
            'medicationList' => {
              'medication' => [vista_medication_with_dispenses]
            }
          },
          'oracle-health' => nil
        }
      end

      it 'includes dispenses in Vista prescriptions' do
        prescriptions = subject.parse(response_with_vista_dispenses)[:prescriptions]

        expect(prescriptions.size).to eq(1)
        vista_prescription = prescriptions.first

        expect(vista_prescription.dispenses).to be_an(Array)
        expect(vista_prescription.dispenses.size).to eq(2)

        first_dispense = vista_prescription.dispenses.first
        expect(first_dispense[:status]).to eq('dispensed')
        expect(first_dispense[:refill_date]).to eq('2025-07-14T04:00:00.000Z')
        expect(first_dispense[:refill_submit_date]).to eq('2025-07-13T04:00:00.000Z')
        expect(first_dispense[:facility_name]).to eq('SLC4')
        expect(first_dispense[:instructions]).to eq('APPLY TEASPOONFUL(S) TO THE AFFECTED AREA EVERY DAY')
        expect(first_dispense[:quantity]).to eq(1)
        expect(first_dispense[:prescription_name]).to eq('COAL TAR 2.5% TOP SOLN')
        expect(first_dispense[:id]).to eq('rf-1')
        expect(first_dispense[:prescription_number]).to eq('RX001')
        expect(first_dispense[:cmop_division_phone]).to eq('800-555-0100')
        expect(first_dispense[:cmop_ndc_number]).to eq('12345-678-90')
        expect(first_dispense[:remarks]).to eq('Handle with care')
        expect(first_dispense[:dial_cmop_division_phone]).to eq('8005550100')
        expect(first_dispense[:disclaimer]).to eq('This is a test disclaimer')
      end
    end

    context 'with Oracle Health prescriptions containing dispenses' do
      let(:oracle_medication_with_dispenses) do
        oracle_health_medication_data.merge(
          'contained' => [
            {
              'resourceType' => 'MedicationDispense',
              'id' => 'dispense-1',
              'status' => 'completed',
              'whenHandedOver' => '2025-01-15T10:00:00Z',
              'quantity' => { 'value' => 30 },
              'location' => { 'display' => '648-PHARMACY' },
              'dosageInstruction' => [
                {
                  'text' => 'See Instructions, daily, 1 EA, 0 Refill(s)'
                }
              ],
              'medicationCodeableConcept' => {
                'text' => 'amLODIPine (amLODIPine 5 mg tablet)'
              }
            },
            {
              'resourceType' => 'MedicationDispense',
              'id' => 'dispense-2',
              'status' => 'completed',
              'whenHandedOver' => '2025-01-29T14:30:00Z',
              'quantity' => { 'value' => 30 },
              'location' => { 'display' => '648-PHARMACY' },
              'dosageInstruction' => [
                {
                  'text' => 'See Instructions, daily, 1 EA, 0 Refill(s)'
                }
              ],
              'medicationCodeableConcept' => {
                'text' => 'amLODIPine (amLODIPine 5 mg tablet)'
              }
            }
          ]
        )
      end

      let(:response_with_oracle_dispenses) do
        {
          'vista' => nil,
          'oracle-health' => {
            'entry' => [
              {
                'resource' => oracle_medication_with_dispenses
              }
            ]
          }
        }
      end

      before do
        allow(Rails.cache).to receive(:read).with('uhd:facility_names:648').and_return('Portland VA Medical Center')
        allow(Rails.cache).to receive(:exist?).with('uhd:facility_names:648').and_return(true)
      end

      it 'includes dispenses in Oracle Health prescriptions' do
        prescriptions = subject.parse(response_with_oracle_dispenses)[:prescriptions]

        expect(prescriptions.size).to eq(1)
        oracle_prescription = prescriptions.first

        expect(oracle_prescription.dispenses).to be_an(Array)
        expect(oracle_prescription.dispenses.size).to eq(2)

        first_dispense = oracle_prescription.dispenses.first
        expect(first_dispense[:status]).to eq('completed')
        expect(first_dispense[:refill_date]).to eq('2025-01-15T10:00:00Z')
        expect(first_dispense[:facility_name]).to eq('Portland VA Medical Center')
        expect(first_dispense[:instructions]).to eq('See Instructions, daily, 1 EA, 0 Refill(s)')
        expect(first_dispense[:quantity]).to eq('30')
        expect(first_dispense[:prescription_name]).to eq('amLODIPine (amLODIPine 5 mg tablet)')
        expect(first_dispense[:id]).to eq('dispense-1')
        # Verify Vista-only fields are nil for Oracle Health
        expect(first_dispense[:refill_submit_date]).to be_nil
        expect(first_dispense[:prescription_number]).to be_nil
        expect(first_dispense[:cmop_division_phone]).to be_nil
        expect(first_dispense[:cmop_ndc_number]).to be_nil
        expect(first_dispense[:remarks]).to be_nil
        expect(first_dispense[:dial_cmop_division_phone]).to be_nil
        expect(first_dispense[:disclaimer]).to be_nil
      end
    end

    context 'with prescriptions without dispenses' do
      it 'includes empty dispenses array for Vista prescriptions without rxRFRecords' do
        prescriptions = subject.parse(unified_response)[:prescriptions]

        vista_prescription = prescriptions.find { |p| p.prescription_id == '28148665' }
        expect(vista_prescription.dispenses).to eq([])
      end

      it 'includes empty dispenses array for Oracle Health prescriptions without MedicationDispense' do
        oracle_only_response = {
          'vista' => nil,
          'oracle-health' => {
            'entry' => [
              {
                'resource' => {
                  'resourceType' => 'MedicationRequest',
                  'id' => 'no-dispenses',
                  'status' => 'active',
                  'authoredOn' => '2025-01-29T19:41:43Z',
                  'medicationCodeableConcept' => {
                    'text' => 'Test Medication'
                  }
                }
              }
            ]
          }
        }

        prescriptions = subject.parse(oracle_only_response)[:prescriptions]
        expect(prescriptions.size).to eq(1)
        expect(prescriptions.first.dispenses).to eq([])
      end
    end

    context 'with missing provider information' do
      let(:vista_medication_no_provider) do
        vista_medication_data.except('providerLastName', 'providerFirstName')
      end

      let(:oracle_medication_no_requester) do
        oracle_health_medication_data.except('requester')
      end

      let(:response_with_missing_providers) do
        {
          'vista' => { 'medicationList' => { 'medication' => [vista_medication_no_provider] } },
          'oracle-health' => {
            'entry' => [
              {
                'resource' => oracle_medication_no_requester
              }
            ]
          }
        }
      end

      it 'handles missing provider data gracefully' do
        prescriptions = subject.parse(response_with_missing_providers)[:prescriptions]

        expect(prescriptions.size).to eq(2)
        vista_prescription = prescriptions.find { |p| p.prescription_id == '28148665' }
        oracle_prescription = prescriptions.find { |p| p.prescription_id == '15208365735' }

        expect(vista_prescription.provider_name).to be_nil
        expect(oracle_prescription.provider_name).to be_nil
      end

      it 'handles partial VistA provider data (only last name)' do
        partial_data = vista_medication_data.except('providerFirstName')
        response = {
          'vista' => { 'medicationList' => { 'medication' => [partial_data] } },
          'oracle-health' => nil
        }

        prescriptions = subject.parse(response)[:prescriptions]
        expect(prescriptions.first.provider_name).to eq('SMITH')
      end

      it 'handles partial VistA provider data (only first name)' do
        partial_data = vista_medication_data.except('providerLastName')
        response = {
          'vista' => { 'medicationList' => { 'medication' => [partial_data] } },
          'oracle-health' => nil
        }

        prescriptions = subject.parse(response)[:prescriptions]
        expect(prescriptions.first.provider_name).to eq('JOHN')
      end
    end

    context 'dial_cmop_division_phone field' do
      it 'maps dialCmopDivisionPhone from Vista prescriptions' do
        prescriptions = subject.parse(unified_response)[:prescriptions]
        vista_prescription = prescriptions.find { |p| p.prescription_id == '28148665' }

        expect(vista_prescription.dial_cmop_division_phone).to eq('555-DIAL')
      end

      it 'sets dial_cmop_division_phone to null for Oracle Health prescriptions' do
        prescriptions = subject.parse(unified_response)[:prescriptions]
        oracle_prescription = prescriptions.find { |p| p.prescription_id == '15208365735' }

        expect(oracle_prescription.dial_cmop_division_phone).to be_nil
      end
    end

    context 'with remarks field' do
      context 'VistA prescriptions' do
        it 'includes remarks from VistA data' do
          prescriptions = subject.parse(unified_response)[:prescriptions]
          vista_prescription = prescriptions.find { |p| p.prescription_id == '28148665' }

          expect(vista_prescription.remarks).to eq('TEST REMARKS FOR VISTA')
        end

        it 'returns nil when remarks is not present' do
          vista_data_without_remarks = vista_medication_data.merge('remarks' => nil)
          response = {
            'vista' => { 'medicationList' => { 'medication' => [vista_data_without_remarks] } },
            'oracle-health' => nil
          }

          prescriptions = subject.parse(response)[:prescriptions]
          expect(prescriptions.first.remarks).to be_nil
        end
      end

      context 'Oracle Health prescriptions' do
        it 'concatenates all note.text fields' do
          prescriptions = subject.parse(unified_response)[:prescriptions]
          oracle_prescription = prescriptions.find { |p| p.prescription_id == '15208365735' }

          expect(oracle_prescription.remarks).to eq('Take with food. May cause dizziness.')
        end

        it 'returns nil when note array is empty' do
          oracle_data_without_notes = oracle_health_medication_data.merge('note' => [])
          response = {
            'vista' => nil,
            'oracle-health' => {
              'entry' => [
                {
                  'resource' => oracle_data_without_notes
                }
              ]
            }
          }

          prescriptions = subject.parse(response)[:prescriptions]
          expect(prescriptions.first.remarks).to be_nil
        end

        it 'returns nil when note is not present' do
          oracle_data_without_notes = oracle_health_medication_data.dup
          oracle_data_without_notes.delete('note')
          response = {
            'vista' => nil,
            'oracle-health' => {
              'entry' => [
                {
                  'resource' => oracle_data_without_notes
                }
              ]
            }
          }

          prescriptions = subject.parse(response)[:prescriptions]
          expect(prescriptions.first.remarks).to be_nil
        end

        it 'handles single note' do
          oracle_data_with_single_note = oracle_health_medication_data.merge(
            'note' => [{ 'text' => 'Single note text' }]
          )
          response = {
            'vista' => nil,
            'oracle-health' => {
              'entry' => [
                {
                  'resource' => oracle_data_with_single_note
                }
              ]
            }
          }

          prescriptions = subject.parse(response)[:prescriptions]
          expect(prescriptions.first.remarks).to eq('Single note text')
        end

        it 'handles multiple notes' do
          oracle_data_with_multiple_notes = oracle_health_medication_data.merge(
            'note' => [
              { 'text' => 'First note' },
              { 'text' => 'Second note' },
              { 'text' => 'Third note' }
            ]
          )
          response = {
            'vista' => nil,
            'oracle-health' => {
              'entry' => [
                {
                  'resource' => oracle_data_with_multiple_notes
                }
              ]
            }
          }

          prescriptions = subject.parse(response)[:prescriptions]
          expect(prescriptions.first.remarks).to eq('First note Second note Third note')
        end

        it 'filters out notes without text field' do
          oracle_data_with_mixed_notes = oracle_health_medication_data.merge(
            'note' => [
              { 'text' => 'Valid note' },
              { 'authorReference' => 'Practitioner/123' },
              { 'text' => 'Another valid note' }
            ]
          )
          response = {
            'vista' => nil,
            'oracle-health' => {
              'entry' => [
                {
                  'resource' => oracle_data_with_mixed_notes
                }
              ]
            }
          }

          prescriptions = subject.parse(response)[:prescriptions]
          expect(prescriptions.first.remarks).to eq('Valid note Another valid note')
        end

        it 'filters out notes with empty text' do
          oracle_data_with_empty_text = oracle_health_medication_data.merge(
            'note' => [
              { 'text' => 'Valid note' },
              { 'text' => '' },
              { 'text' => 'Another valid note' }
            ]
          )
          response = {
            'vista' => nil,
            'oracle-health' => {
              'entry' => [
                {
                  'resource' => oracle_data_with_empty_text
                }
              ]
            }
          }

          prescriptions = subject.parse(response)[:prescriptions]
          expect(prescriptions.first.remarks).to eq('Valid note Another valid note')
        end
      end
    end
  end

  describe '#parse metadata' do
    before do
      allow(Flipper).to receive(:enabled?).with(:mhv_medications_display_pending_meds, user).and_return(false)
    end

    it 'returns a hash with prescriptions and metadata keys' do
      result = subject.parse(unified_response)

      expect(result).to be_a(Hash)
      expect(result).to have_key(:prescriptions)
      expect(result).to have_key(:metadata)
      expect(result[:prescriptions]).to be_an(Array)
      expect(result[:metadata]).to have_key(:has_failed_stations)
    end

    it 'returns has_failed_stations: false when no sources failed' do
      result = subject.parse(unified_response)

      expect(result[:metadata][:has_failed_stations]).to be false
    end

    it 'returns has_failed_stations: true when VistA has failedStationList' do
      response_with_failure = {
        'vista' => {
          'failedStationList' => 'Station-979,Station-442',
          'medicationList' => { 'medication' => [vista_medication_data] }
        },
        'oracle-health' => { 'entry' => [] }
      }

      result = subject.parse(response_with_failure)

      expect(result[:metadata][:has_failed_stations]).to be true
    end

    it 'returns has_failed_stations: true when Oracle Health has error OperationOutcome' do
      response_with_oh_failure = {
        'vista' => { 'medicationList' => { 'medication' => [vista_medication_data] } },
        'oracle-health' => {
          'entry' => [
            {
              'resource' => {
                'resourceType' => 'OperationOutcome',
                'id' => 'err-1',
                'issue' => [
                  { 'severity' => 'error', 'code' => 'exception', 'diagnostics' => 'Exhausted retry attempts' }
                ]
              }
            }
          ]
        }
      }

      result = subject.parse(response_with_oh_failure)

      expect(result[:metadata][:has_failed_stations]).to be true
    end

    it 'returns has_failed_stations: false when Oracle Health is empty (patient not registered)' do
      response_oh_empty = {
        'vista' => { 'medicationList' => { 'medication' => [vista_medication_data] } },
        'oracle-health' => {}
      }

      result = subject.parse(response_oh_empty)

      expect(result[:metadata][:has_failed_stations]).to be false
    end

    it 'raises an ArgumentError when body is nil' do
      expect { subject.parse(nil) }.to raise_error(ArgumentError, 'UHD returned an empty response body')
    end
  end

  describe '#parse upstream log counts' do
    before do
      allow(Flipper).to receive(:enabled?).with(:mhv_medications_display_pending_meds, user).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:mhv_medications_management_improvements, user).and_return(false)
    end

    it 'logs counts when both sources return medications' do
      allow(Rails.logger).to receive(:info)
      allow(Rails.logger).to receive(:warn)

      subject.parse(unified_response)

      expect(Rails.logger).to have_received(:info).with(
        hash_including(
          message: 'UHD prescriptions upstream parse counts',
          vista_raw_medications_parsed: 1,
          oracle_raw_medications_parsed: 1,
          vista_medication_list_is_array: true,
          oracle_entry_is_array: true,
          vista_failed_station_list: nil,
          service: 'unified_health_data'
        )
      )
    end

    it 'logs zero counts when upstream returns empty data for both sources' do
      empty_response = { 'vista' => {}, 'oracle-health' => {} }

      allow(Rails.logger).to receive(:info)

      subject.parse(empty_response)

      expect(Rails.logger).to have_received(:info).with(
        hash_including(
          message: 'UHD prescriptions upstream parse counts',
          vista_raw_medications_parsed: 0,
          oracle_raw_medications_parsed: 0,
          vista_medication_list_is_array: false,
          oracle_entry_is_array: false,
          vista_failed_station_list: nil,
          service: 'unified_health_data'
        )
      )
    end

    it 'logs failed station list when VistA stations fail' do
      response_with_failure = {
        'vista' => {
          'failedStationList' => 'Station-979,Station-442',
          'successfulStationList' => nil,
          'medicationList' => nil
        },
        'oracle-health' => {}
      }

      allow(Rails.logger).to receive(:info)

      subject.parse(response_with_failure)

      expect(Rails.logger).to have_received(:info).with(
        hash_including(
          message: 'UHD prescriptions upstream parse counts',
          vista_raw_medications_parsed: 0,
          oracle_raw_medications_parsed: 0,
          vista_medication_list_is_array: false,
          oracle_entry_is_array: false,
          vista_failed_station_list: 'Station-979,Station-442',
          service: 'unified_health_data'
        )
      )
    end

    it 'logs partial data when some VistA stations fail but others succeed' do
      allow(Rails.logger).to receive(:info)
      allow(Rails.logger).to receive(:warn)

      response_partial = {
        'vista' => {
          'failedStationList' => 'Station-442',
          'medicationList' => { 'medication' => [vista_medication_data] }
        },
        'oracle-health' => {
          'entry' => [{ 'resource' => oracle_health_medication_data }]
        }
      }

      subject.parse(response_partial)

      expect(Rails.logger).to have_received(:info).with(
        hash_including(
          message: 'UHD prescriptions upstream parse counts',
          vista_raw_medications_parsed: 1,
          oracle_raw_medications_parsed: 1,
          vista_medication_list_is_array: true,
          oracle_entry_is_array: true,
          vista_failed_station_list: 'Station-442',
          service: 'unified_health_data'
        )
      )
    end
  end

  describe 'status mapping consolidation (legacy V1 behavior)' do
    let(:adapter) { subject }

    let(:vista_medication_with_refill_status) do
      vista_medication_data.merge(
        'prescriptionId' => 'vista-with-status',
        'refillStatus' => 'active',
        'dispStatus' => 'Active'
      )
    end

    let(:oracle_medication_request) do
      oracle_health_medication_data.merge(
        'id' => 'oracle-request',
        'status' => 'active',
        'dispenseRequest' => {
          'numberOfRepeatsAllowed' => 5,
          'quantity' => { 'value' => 30 }
        }
      )
    end

    let(:unified_body) do
      {
        'vista' => {
          'medicationList' => {
            'medication' => [vista_medication_data.merge('dispStatus' => 'Active')]
          }
        },
        'oracle-health' => {
          'entry' => [{ 'resource' => oracle_health_medication_data }]
        }
      }
    end

    let(:combined_body) do
      {
        'vista' => {
          'medicationList' => {
            'medication' => [vista_medication_with_refill_status]
          }
        },
        'oracle-health' => {
          'entry' => [{ 'resource' => oracle_medication_request }]
        }
      }
    end

    let(:vista_active) do
      vista_medication_data.merge(
        'prescriptionId' => 'vista-active',
        'refillStatus' => 'active',
        'dispStatus' => nil
      )
    end

    let(:vista_expired) do
      vista_medication_data.merge(
        'prescriptionId' => 'vista-expired',
        'refillStatus' => 'expired',
        'dispStatus' => nil
      )
    end

    let(:vista_discontinued) do
      vista_medication_data.merge(
        'prescriptionId' => 'vista-discontinued',
        'refillStatus' => 'discontinued',
        'dispStatus' => nil
      )
    end

    let(:vista_hold) do
      vista_medication_data.merge(
        'prescriptionId' => 'vista-hold',
        'refillStatus' => 'hold',
        'dispStatus' => nil
      )
    end

    let(:vista_provider_hold) do
      vista_medication_data.merge(
        'prescriptionId' => 'vista-provider-hold',
        'refillStatus' => 'providerHold',
        'dispStatus' => nil
      )
    end

    let(:vista_submitted) do
      vista_medication_data.merge(
        'prescriptionId' => 'vista-submitted',
        'refillStatus' => 'submitted',
        'dispStatus' => nil
      )
    end

    let(:oracle_active) do
      oracle_health_medication_data.merge(
        'id' => 'oracle-active',
        'status' => 'active',
        'dispenseRequest' => {
          'numberOfRepeatsAllowed' => 5,
          'quantity' => { 'value' => 30 }
        }
      )
    end

    let(:oracle_on_hold) do
      oracle_health_medication_data.merge(
        'id' => 'oracle-on-hold',
        'status' => 'on-hold',
        'dispenseRequest' => {
          'numberOfRepeatsAllowed' => 5,
          'quantity' => { 'value' => 30 }
        }
      )
    end

    let(:oracle_stopped) do
      oracle_health_medication_data.merge(
        'id' => 'oracle-stopped',
        'status' => 'stopped',
        'dispenseRequest' => {
          'numberOfRepeatsAllowed' => 0,
          'quantity' => { 'value' => 30 }
        }
      )
    end

    let(:vista_response) do
      {
        'vista' => {
          'medicationList' => {
            'medication' => [
              vista_active,
              vista_expired,
              vista_discontinued,
              vista_hold,
              vista_provider_hold,
              vista_submitted
            ]
          }
        },
        'oracle-health' => nil
      }
    end

    let(:oracle_response) do
      {
        'vista' => nil,
        'oracle-health' => {
          'entry' => [
            { 'resource' => oracle_active },
            { 'resource' => oracle_on_hold },
            { 'resource' => oracle_stopped }
          ]
        }
      }
    end

    let(:combined_response) do
      {
        'vista' => {
          'medicationList' => {
            'medication' => [vista_active, vista_expired]
          }
        },
        'oracle-health' => {
          'entry' => [
            { 'resource' => oracle_active },
            { 'resource' => oracle_on_hold }
          ]
        }
      }
    end

    let(:vista_only_body) do
      {
        'vista' => {
          'medicationList' => {
            'medication' => [vista_medication_with_refill_status]
          }
        }
      }
    end

    let(:oracle_only_body) do
      {
        'oracle-health' => {
          'entry' => [{ 'resource' => oracle_medication_request }]
        }
      }
    end

    before do
      allow(Flipper).to receive(:enabled?).with(:mhv_medications_display_pending_meds, user).and_return(false)
    end

    context 'status mapping (legacy V1 behavior)' do
      it 'returns legacy refill_status values for VistA prescriptions' do
        prescriptions = subject.parse(vista_response)[:prescriptions]

        statuses = prescriptions.map(&:refill_status)
        expect(statuses).to include('active', 'expired', 'discontinued', 'hold', 'providerHold', 'submitted')
      end

      it 'returns legacy refill_status values for Oracle Health prescriptions' do
        prescriptions = subject.parse(oracle_response)[:prescriptions]

        # Oracle adapter normalizes FHIR status to legacy VistA-style status
        statuses = prescriptions.map(&:refill_status)
        expect(statuses).to include('active', 'providerHold', 'discontinued')
      end

      it 'returns legacy statuses for combined prescriptions' do
        prescriptions = subject.parse(combined_response)[:prescriptions]

        statuses = prescriptions.map(&:refill_status)
        # Should have legacy raw statuses only
        expect(statuses).not_to include('Active', 'Inactive', 'Active: On Hold')
        expect(statuses).to include('active', 'expired', 'providerHold')
      end
    end
  end

  shared_context 'shipped tracking test data' do
    let(:shipped_date) { 5.days.ago.utc.iso8601(3) }

    let(:vista_med_with_tracking) do
      vista_medication_data.merge(
        'isTrackable' => true,
        'dispStatus' => 'Active: Shipped',
        'trackingList' => {
          'tracking' => [
            {
              'trackingNumber' => '1Z999AA10123456784',
              'completeDateTime' => shipped_date,
              'carrier' => 'UPS',
              'otherPrescriptionListIncluded' => []
            }
          ]
        },
        'rxRFRecords' => {
          'rfRecord' => [
            {
              'refillStatus' => 'completed',
              'dispensedDate' => 10.days.ago.utc.iso8601(3),
              'refillDate' => 12.days.ago.utc.iso8601(3),
              'facilityName' => 'SLC4',
              'sig' => 'TAKE ONE',
              'quantity' => 30,
              'prescriptionName' => 'COAL TAR 2.5% TOP SOLN',
              'id' => 1001,
              'prescriptionNumber' => '3636485'
            }
          ]
        }
      )
    end

    let(:vista_response_with_tracking) do
      {
        'vista' => {
          'medicationList' => {
            'medication' => [vista_med_with_tracking]
          }
        }
      }
    end

    # Recently dispensed (filled) but not yet shipped: Active disp_status, a
    # recent dispensed date, and no tracking entries.
    let(:dispensed_date) { 3.days.ago.utc.iso8601(3) }

    let(:vista_med_awaiting_tracking) do
      vista_medication_data.merge(
        'dispStatus' => 'Active',
        'isTrackable' => false,
        'dispensedDate' => dispensed_date,
        'rxRFRecords' => {
          'rfRecord' => [
            {
              'refillStatus' => 'active',
              'dispensedDate' => dispensed_date,
              'prescriptionName' => 'COAL TAR 2.5% TOP SOLN',
              'id' => 1002,
              'prescriptionNumber' => '3636485'
            }
          ]
        }
      )
    end

    let(:awaiting_tracking_response) do
      {
        'vista' => {
          'medicationList' => {
            'medication' => [vista_med_awaiting_tracking]
          }
        }
      }
    end
  end

  describe 'shipped tracking logic when mhv_medications_management_improvements is enabled' do
    include_context 'shipped tracking test data'

    before do
      allow(Flipper).to receive(:enabled?).with(:mhv_medications_display_pending_meds, user).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:mhv_medications_management_improvements, user).and_return(true)
    end

    context 'when shipped within 15-day window' do
      it 'preserves disp_status as Active: Shipped from source' do
        result = subject.parse(vista_response_with_tracking)
        rx = result[:prescriptions].first

        expect(rx.disp_status).to eq('Active: Shipped')
      end

      it 'preserves is_trackable as true' do
        result = subject.parse(vista_response_with_tracking)
        rx = result[:prescriptions].first

        expect(rx.is_trackable).to be true
      end
    end

    context 'when shipped beyond 15-day window' do
      let(:shipped_date) { 20.days.ago.utc.iso8601(3) }

      it 'preserves disp_status as Active: Shipped from source' do
        result = subject.parse(vista_response_with_tracking)
        rx = result[:prescriptions].first

        expect(rx.disp_status).to eq('Active: Shipped')
      end

      it 'sets is_trackable to false' do
        result = subject.parse(vista_response_with_tracking)
        rx = result[:prescriptions].first

        expect(rx.is_trackable).to be false
      end
    end

    context 'when shipped exactly 15 days ago (boundary)' do
      let(:frozen_time) { Time.zone.parse('2026-03-12 12:00:00 UTC') }
      let(:shipped_date) { (frozen_time - 15.days).utc.iso8601(3) }

      it 'preserves is_trackable as true (inclusive boundary)' do
        Timecop.freeze(frozen_time) do
          result = subject.parse(vista_response_with_tracking)
          rx = result[:prescriptions].first

          expect(rx.is_trackable).to be true
        end
      end
    end

    context 'when prescription has no tracking info' do
      it 'does not modify disp_status or is_trackable' do
        # Default vista_medication_data has no trackingList
        result = subject.parse(unified_response)
        vista_rx = result[:prescriptions].find { |p| p.prescription_id == '28148665' }

        expect(vista_rx.disp_status).to be_nil
        expect(vista_rx.is_trackable).to be false
      end
    end

    context 'when prescription has multiple tracking entries' do
      let(:vista_med_with_multiple_tracking) do
        vista_med_with_tracking.merge(
          'trackingList' => {
            'tracking' => [
              {
                'trackingNumber' => '1Z999AA10123456784',
                'completeDateTime' => 20.days.ago.utc.iso8601(3),
                'carrier' => 'UPS',
                'otherPrescriptionListIncluded' => []
              },
              {
                'trackingNumber' => '1Z999AA10123456785',
                'completeDateTime' => 3.days.ago.utc.iso8601(3),
                'carrier' => 'USPS',
                'otherPrescriptionListIncluded' => []
              }
            ]
          }
        )
      end

      it 'uses the most recent shipped date for the window check' do
        response = {
          'vista' => {
            'medicationList' => {
              'medication' => [vista_med_with_multiple_tracking]
            }
          }
        }

        result = subject.parse(response)
        rx = result[:prescriptions].first

        # Most recent is 3 days ago (within window) — is_trackable stays true
        expect(rx.disp_status).to eq('Active: Shipped')
        expect(rx.is_trackable).to be true
      end
    end

    context 'when tracking has invalid shipped date' do
      let(:vista_med_with_bad_tracking) do
        vista_med_with_tracking.merge(
          'trackingList' => {
            'tracking' => [
              {
                'trackingNumber' => '1Z999AA10123456784',
                'completeDateTime' => 'not-a-date',
                'carrier' => 'UPS',
                'otherPrescriptionListIncluded' => []
              }
            ]
          }
        )
      end

      it 'skips the prescription without error' do
        response = {
          'vista' => {
            'medicationList' => {
              'medication' => [vista_med_with_bad_tracking]
            }
          }
        }

        result = subject.parse(response)
        rx = result[:prescriptions].first

        expect(rx.disp_status).to eq('Active: Shipped')
        expect(rx.is_trackable).to be true
      end
    end

    context 'with Oracle Health prescription with tracking' do
      let(:oracle_med_with_tracking) do
        oracle_health_medication_data.merge(
          'contained' => [
            {
              'resourceType' => 'MedicationDispense',
              'id' => 'dispense-1',
              'whenHandedOver' => '2025-01-15T10:00:00Z',
              'quantity' => { 'value' => 30 },
              'location' => { 'display' => 'Main Pharmacy' },
              'extension' => [
                {
                  'url' => 'http://va.gov/fhir/StructureDefinition/shipping-info',
                  'extension' => [
                    { 'url' => 'Shipped Date', 'valueString' => 3.days.ago.utc.strftime('%Y-%m-%d %H:%M:%S.0') },
                    { 'url' => 'Tracking Number', 'valueString' => '1Z999AA10123456784' },
                    { 'url' => 'Delivery Service', 'valueString' => 'UPS' }
                  ]
                }
              ]
            }
          ]
        )
      end

      it 'does not apply shipped tracking logic since Oracle Health does not produce Active: Shipped status' do
        response = {
          'oracle-health' => {
            'entry' => [{ 'resource' => oracle_med_with_tracking }]
          }
        }

        result = subject.parse(response)
        rx = result[:prescriptions].first

        expect(rx.disp_status).not_to eq('Active: Shipped')
        expect(rx.is_trackable).to be true
      end
    end
  end

  describe 'shipped tracking logic when mhv_medications_management_improvements is disabled' do
    include_context 'shipped tracking test data'

    before do
      allow(Flipper).to receive(:enabled?).with(:mhv_medications_display_pending_meds, user).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:mhv_medications_management_improvements, user).and_return(false)
    end

    it 'does not apply shipped tracking logic' do
      result = subject.parse(vista_response_with_tracking)
      rx = result[:prescriptions].first

      expect(rx.disp_status).to eq('Active: Shipped')
      expect(rx.is_trackable).to be true
    end

    it 'defaults is_awaiting_tracking to false (never nil) so the serialized value stays boolean' do
      result = subject.parse(awaiting_tracking_response)
      rx = result[:prescriptions].first

      expect(rx.is_awaiting_tracking).to be false
    end
  end

  # CMOP handoff gap: after a refill is requested VistA shows "Active: Refill in Process", then
  # transmits the fill to CMOP and momentarily drops the aggregate disp_status back to plain
  # "Active" (is_refillable true) until a dispense/shipment lands. This bridge restores the
  # in-process display during that window, anchored on the refill-record date and released early
  # once a fill lands. Unlike the submission bridge it leaves is_refillable/is_trackable alone.
  describe '#cmop_refill_in_process? / CMOP in-process bridge' do
    def cmop_rx(rf_submits: [], dispensed: nil, **attrs)
      defaults = {
        id: '12345',
        disp_status: 'Active',
        source_ehr: UnifiedHealthData::Prescription::SOURCE_EHR_VISTA,
        is_refillable: true,
        is_trackable: true,
        tracking: [],
        dispenses: rf_submits.map { |d| { refill_submit_date: d } },
        sorted_dispensed_date: dispensed
      }
      UnifiedHealthData::Prescription.new(defaults.merge(attrs))
    end

    describe '#cmop_refill_in_process?' do
      subject(:adapter) { described_class.new }

      it 'is true for a recent refill record with no dispense or shipment yet' do
        rx = cmop_rx(rf_submits: [5.days.ago.iso8601])
        expect(adapter.send(:cmop_refill_in_process?, rx)).to be(true)
      end

      it 'is false when there are no refill records' do
        rx = cmop_rx(rf_submits: [])
        expect(adapter.send(:cmop_refill_in_process?, rx)).to be(false)
      end

      it 'is nil-safe when the refill-record submit date is an unparseable string' do
        rx = cmop_rx(rf_submits: ['not-a-date'])
        expect(adapter.send(:cmop_refill_in_process?, rx)).to be(false)
      end

      it 'is false when the most recent refill record is older than the CMOP window' do
        rx = cmop_rx(rf_submits: [20.days.ago.iso8601])
        expect(adapter.send(:cmop_refill_in_process?, rx)).to be(false)
      end

      it 'holds at the window boundary and releases just beyond it' do
        travel_to(Time.zone.parse('2026-03-12 12:00:00 UTC')) do
          within = cmop_rx(rf_submits: [15.days.ago.iso8601])
          beyond = cmop_rx(rf_submits: [16.days.ago.iso8601])
          expect(adapter.send(:cmop_refill_in_process?, within)).to be(true)
          expect(adapter.send(:cmop_refill_in_process?, beyond)).to be(false)
        end
      end

      it 'uses the most recent refill-record submit date across multiple records' do
        # Oldest record is out of window, most recent is within: the max date must win.
        rx = cmop_rx(rf_submits: [40.days.ago.iso8601, 3.days.ago.iso8601])
        expect(adapter.send(:cmop_refill_in_process?, rx)).to be(true)
      end

      it 'is false when a dispense landed on/after the refill-record date' do
        rx = cmop_rx(rf_submits: [3.days.ago.iso8601], dispensed: 1.day.ago.iso8601)
        expect(adapter.send(:cmop_refill_in_process?, rx)).to be(false)
      end

      it 'stays true when the only dispense predates the refill-record date (prior cycle)' do
        rx = cmop_rx(rf_submits: [1.day.ago.iso8601], dispensed: 30.days.ago.iso8601)
        expect(adapter.send(:cmop_refill_in_process?, rx)).to be(true)
      end

      it 'is false when a shipment completed on/after the refill-record date' do
        rx = cmop_rx(rf_submits: [2.days.ago.iso8601], tracking: [{ complete_date_time: 1.day.ago.iso8601 }])
        expect(adapter.send(:cmop_refill_in_process?, rx)).to be(false)
      end

      it 'stays true when the only shipment predates the refill-record date (stale prior-cycle tracking)' do
        rx = cmop_rx(rf_submits: [1.day.ago.iso8601], tracking: [{ complete_date_time: 30.days.ago.iso8601 }])
        expect(adapter.send(:cmop_refill_in_process?, rx)).to be(true)
      end
    end

    describe '#cmop_in_process_window_days' do
      subject(:adapter) { described_class.new }

      it 'returns the configured Settings value when positive' do
        allow(Settings.mhv.uhd).to receive(:cmop_in_process_window_days).and_return(30)
        expect(adapter.send(:cmop_in_process_window_days)).to eq(30)
      end

      it 'falls back to the default when the Settings value is non-positive' do
        allow(Settings.mhv.uhd).to receive(:cmop_in_process_window_days).and_return(0)
        expect(adapter.send(:cmop_in_process_window_days)).to eq(15)
      end

      it 'falls back to the default when the Settings value is nil' do
        allow(Settings.mhv.uhd).to receive(:cmop_in_process_window_days).and_return(nil)
        expect(adapter.send(:cmop_in_process_window_days)).to eq(15)
      end

      it 'honors a widened window (a request past the default holds under a larger setting)' do
        allow(Settings.mhv.uhd).to receive(:cmop_in_process_window_days).and_return(30)
        rx = cmop_rx(rf_submits: [20.days.ago.iso8601])
        expect(adapter.send(:cmop_refill_in_process?, rx)).to be(true)
      end
    end

    describe '#apply_cmop_in_process_bridge' do
      subject(:adapter) { described_class.new }

      it 'bridges a VistA prescription to Active: Refill in Process without touching is_refillable or is_trackable' do
        rx = cmop_rx(rf_submits: [5.days.ago.iso8601], is_refillable: true, is_trackable: true)
        adapter.send(:apply_cmop_in_process_bridge, [rx])

        expect(rx.disp_status).to eq('Active: Refill in Process')
        expect(rx.refill_status).to eq('refillinprocess')
        expect(rx.is_refillable).to be true
        expect(rx.is_trackable).to be true
      end

      it 'does not bridge an Oracle Health prescription (OH surfaces in-process from its own Tasks)' do
        rx = cmop_rx(rf_submits: [5.days.ago.iso8601], source_ehr: UnifiedHealthData::Prescription::SOURCE_EHR_ORACLE_HEALTH)
        adapter.send(:apply_cmop_in_process_bridge, [rx])

        expect(rx.disp_status).to eq('Active')
      end

      it 'only bridges prescriptions still showing plain Active (leaves Active: Shipped untouched)' do
        rx = cmop_rx(rf_submits: [5.days.ago.iso8601], disp_status: 'Active: Shipped')
        adapter.send(:apply_cmop_in_process_bridge, [rx])

        expect(rx.disp_status).to eq('Active: Shipped')
      end
    end

    describe 'integration through #parse' do
      let(:vista_med_cmop) do
        vista_medication_data.merge(
          'dispStatus' => 'Active',
          'isRefillable' => true,
          'dispensedDate' => nil,
          'rxRFRecords' => {
            'rfRecord' => [
              {
                'id' => 'rf-1',
                'refillStatus' => 'refillinprocess',
                'refillSubmitDate' => 5.days.ago.utc.iso8601(3),
                'dispensedDate' => nil
              }
            ]
          }
        )
      end

      let(:cmop_response) do
        { 'vista' => { 'medicationList' => { 'medication' => [vista_med_cmop] } } }
      end

      before do
        allow(Flipper).to receive(:enabled?).with(:mhv_medications_display_pending_meds, user).and_return(false)
      end

      context 'when the CMOP bridge flag and MMI are enabled' do
        before do
          allow(Flipper).to receive(:enabled?)
            .with(:mhv_medications_cmop_refill_in_process_bridge, user).and_return(true)
          allow(Flipper).to receive(:enabled?)
            .with(:mhv_medications_management_improvements, user).and_return(true)
        end

        it 'restores Active: Refill in Process and leaves is_refillable true' do
          rx = subject.parse(cmop_response)[:prescriptions].first

          expect(rx.disp_status).to eq('Active: Refill in Process')
          expect(rx.refill_status).to eq('refillinprocess')
          expect(rx.is_refillable).to be true
        end
      end

      context 'when the CMOP bridge flag is disabled' do
        before do
          allow(Flipper).to receive(:enabled?)
            .with(:mhv_medications_cmop_refill_in_process_bridge, user).and_return(false)
          allow(Flipper).to receive(:enabled?)
            .with(:mhv_medications_management_improvements, user).and_return(true)
        end

        it 'leaves the prescription as plain Active (gating preserved)' do
          rx = subject.parse(cmop_response)[:prescriptions].first

          expect(rx.disp_status).to eq('Active')
        end
      end

      context 'when the CMOP bridge flag is enabled but MMI is off' do
        before do
          allow(Flipper).to receive(:enabled?)
            .with(:mhv_medications_cmop_refill_in_process_bridge, user).and_return(true)
          allow(Flipper).to receive(:enabled?)
            .with(:mhv_medications_management_improvements, user).and_return(false)
        end

        it 'leaves the prescription as plain Active (requires MMI)' do
          rx = subject.parse(cmop_response)[:prescriptions].first

          expect(rx.disp_status).to eq('Active')
        end
      end
    end
  end
end
