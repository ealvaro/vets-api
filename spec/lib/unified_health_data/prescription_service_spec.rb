# frozen_string_literal: true

require 'rails_helper'
require 'unified_health_data/prescription_service'
require 'unified_health_data/facility_service'
require 'support/shared_contexts/uhd_security_endpoint'

describe UnifiedHealthData::PrescriptionService, type: :service do
  include ActiveSupport::Testing::TimeHelpers

  subject { described_class }

  include_context 'uhd legacy security endpoint'

  let(:user) { build(:user, :loa3, icn: '1000123456V123456') }
  let(:service) { described_class.new(user) }

  before do
    # Pin every Flipper flag the prescriptions parse path branches on so these specs are
    # deterministic and independent of the test environment's auto-enabled flag defaults.
    # All config/features.yml flags default to enabled in tests, so leaving these unstubbed
    # ties cassette-count and status assertions to that global default. Individual contexts
    # override :mhv_medications_management_improvements where they exercise it.
    allow(Flipper).to receive(:enabled?)
      .with(:mhv_medications_display_pending_meds, anything).and_return(true)
    allow(Flipper).to receive(:enabled?)
      .with(:mhv_medications_oh_renewal_message_rollout, anything).and_return(true)
    allow(Flipper).to receive(:enabled?)
      .with(:mhv_medications_management_improvements, anything).and_return(false)
    allow(Flipper).to receive(:enabled?)
      .with(:mhv_mmi_refill_status_bandaid_temp, anything).and_return(false)
  end

  describe '#get_prescriptions' do
    # All Oracle Health stations present in the VCR cassette
    let(:oh_stations) { %w[556 668 757] }

    before do
      # Freeze today so the generated end_date in service matches VCR cassette date range expectations
      allow(Time.zone).to receive(:today).and_return(Date.new(2026, 3, 25))
      allow(Rails.cache).to receive(:exist?).and_return(false)
    end

    context 'with valid prescription responses', :vcr do
      before do
        # Stub the cache to return facility names for all Oracle Health stations in the cassette
        oh_stations.each do |station|
          allow(Rails.cache).to receive(:read).with("uhd:facility_names:#{station}").and_return('Ambulatory Pharmacy')
          allow(Rails.cache).to receive(:exist?).with("uhd:facility_names:#{station}").and_return(true)
        end

        # Stub facility timezone service for expiration date normalization
        facility_tz_service = instance_double(UnifiedHealthData::FacilityService)
        allow(UnifiedHealthData::FacilityService).to receive(:new).and_return(facility_tz_service)
        allow(facility_tz_service).to receive(:get_facility_timezone).and_return('America/Los_Angeles')
      end

      it 'returns prescriptions from both VistA and Oracle Health' do
        VCR.use_cassette('unified_health_data/get_prescriptions_success') do
          prescriptions = service.get_prescriptions[:prescriptions]

          # Assert stable count from deterministic VCR cassette to catch regressions
          # Clinic-administered medications (category: outpatient, reportedBoolean: false, intent: order)
          # are excluded from the response
          expect(prescriptions.size).to eq(73)

          # Check that prescriptions are UnifiedHealthData::Prescription objects
          expect(prescriptions).to all(be_a(UnifiedHealthData::Prescription))

          # Verify both sources contribute data
          ids = prescriptions.map(&:prescription_id)
          expect(ids).to include('26305871') # VistA
          expect(ids).to include('20848812135') # Oracle Health
        end
      end

      context 'with current_only: true' do
        it 'applies filtering to exclude old discontinued/expired prescriptions' do
          travel_to(Time.zone.parse('2026-03-25 12:00:00')) do
            VCR.use_cassette('unified_health_data/get_prescriptions_success', allow_playback_repeats: true) do
              all_prescriptions = service.get_prescriptions[:prescriptions]
              filtered_prescriptions = service.get_prescriptions(current_only: true)[:prescriptions]

              expect(filtered_prescriptions).not_to be_empty
              expect(filtered_prescriptions.size).to be <= all_prescriptions.size

              # Verify every remaining prescription is either not expired/discontinued,
              # or its expiration is within the 180-day window
              cutoff = 180.days.ago.to_date
              filtered_prescriptions.each do |prescription|
                status = prescription.refill_status.to_s.downcase
                next unless %w[expired discontinued].include?(status)

                expiration = Date.parse(prescription.expiration_date) if prescription.expiration_date.present?
                expect(expiration).to be >= cutoff if expiration
              end
            end
          end
        end
      end

      it 'properly maps VistA prescription fields' do
        VCR.use_cassette('unified_health_data/get_prescriptions_success') do
          prescriptions = service.get_prescriptions[:prescriptions]
          vista_prescription = prescriptions.find { |p| p.prescription_id == '26305871' }

          expect(vista_prescription.refill_status).to eq('refillinprocess')
          expect(vista_prescription.refill_remaining).to eq(4)
          expect(vista_prescription.facility_name).to eq('Dayton Medical Center')
          expect(vista_prescription.prescription_name).to eq('PROMETHAZINE HCL 25MG TAB')
          expect(vista_prescription.instructions).to include('TAKE ONE TABLET BY MOUTH DAILY')
          expect(vista_prescription.station_number).to eq('989')
          expect(vista_prescription.prescription_number).to eq('2721445')
        end
      end

      it 'properly maps Oracle Health prescription fields' do
        # Prescription 20848812135 carries a 'requested' order-Task dated 2026-03-20T18:59:55Z.
        # Freeze time inside the always-enforced in-flight staleness window so the refill
        # still resolves to 'submitted' (and thus is_refillable false via Gate 7).
        travel_to(Time.zone.parse('2026-03-22 12:00:00 UTC')) do
          VCR.use_cassette('unified_health_data/get_prescriptions_success') do
            prescriptions = service.get_prescriptions[:prescriptions]
            oracle_prescription = prescriptions.find { |p| p.prescription_id == '20848812135' }

            expect(oracle_prescription.refill_status).to eq('submitted')
            expect(oracle_prescription.refill_remaining).to eq(1)
            expect(oracle_prescription.facility_name).to eq('Ambulatory Pharmacy')
            expect(oracle_prescription.ordered_date).to eq('2025-11-17T21:21:48Z')
            expect(oracle_prescription.quantity).to eq('18')
            expect(oracle_prescription.expiration_date).to eq('2026-11-16T12:00:00.000Z')
            expect(oracle_prescription.prescription_number).to be_nil # No prescription identifier exists
            expect(oracle_prescription.prescription_name).to eq('albuterol (albuterol 90 mcg inhaler [18g])')
            expect(oracle_prescription.station_number).to eq('668')
            expect(oracle_prescription.is_trackable).to be true
            expect(oracle_prescription.tracking).to be_an(Array)
            expect(oracle_prescription.tracking).not_to be_empty
            expect(oracle_prescription.prescription_source).to eq('VA')
            expect(oracle_prescription.is_refillable).to be false
            expect(oracle_prescription.instructions).to include('Inhalation')
            expect(oracle_prescription.facility_phone_number).to be_nil
          end
        end
      end

      it 'parses prescription number from rx-number and station-prefix identifiers' do
        VCR.use_cassette('unified_health_data/get_prescriptions_success') do
          prescriptions = service.get_prescriptions[:prescriptions]
          rx_with_number = prescriptions.find { |p| p.prescription_id == '20855608527' }

          expect(rx_with_number.prescription_number).to eq('3001-61868975')
        end
      end

      it 'returns nil prescription number when either identifier element is missing' do
        VCR.use_cassette('unified_health_data/get_prescriptions_success') do
          prescriptions = service.get_prescriptions[:prescriptions]
          rx_without_number = prescriptions.find { |p| p.prescription_id == '20848812135' }

          expect(rx_without_number.prescription_number).to be_nil
        end
      end

      it 'maps completed status to discontinued or expired' do
        VCR.use_cassette('unified_health_data/get_prescriptions_success') do
          prescriptions = service.get_prescriptions[:prescriptions]
          completed_prescription = prescriptions.find { |p| p.prescription_id == '20848863583' }

          expect(completed_prescription.refill_status).to be_in(%w[discontinued expired])
          expect(completed_prescription.is_refillable).to be false
          expect(completed_prescription.refill_date).to be_nil
        end
      end

      it 'handles different refill statuses correctly' do
        VCR.use_cassette('unified_health_data/get_prescriptions_success') do
          prescriptions = service.get_prescriptions[:prescriptions]

          # Verify we have prescriptions with various statuses
          statuses = prescriptions.map(&:refill_status).uniq
          expect(statuses.size).to be > 1

          discontinued_prescription = prescriptions.find { |p| p.prescription_id == '26305874' }
          expect(discontinued_prescription.refill_status).to eq('discontinued')
        end
      end

      it 'properly handles Oracle Health FHIR features' do
        VCR.use_cassette('unified_health_data/get_prescriptions_success') do
          prescriptions = service.get_prescriptions[:prescriptions]

          # Test prescription with patientInstruction (should prefer over text)
          oracle_prescription_with_patient_instruction = prescriptions.find { |p| p.prescription_id == '20848812135' }
          expect(oracle_prescription_with_patient_instruction.instructions).to be_a(String)
          expect(oracle_prescription_with_patient_instruction.facility_name).to eq('Ambulatory Pharmacy')
          refill_date = oracle_prescription_with_patient_instruction.refill_date
          expect(refill_date).to be_a(String)
          expect { Time.iso8601(refill_date) }.not_to raise_error
          expect(oracle_prescription_with_patient_instruction.dispensed_date).to be_nil
        end
      end

      context 'Task resource parsing' do
        # Prescription 20848812135 carries a 'requested' order-Task dated 2026-03-20T18:59:55Z.
        # Freeze time inside the always-enforced in-flight staleness window so honored Tasks
        # still resolve to submitted; failed-Task cases below are time-independent.
        around do |example|
          travel_to(Time.zone.parse('2026-03-22 12:00:00 UTC')) { example.run }
        end

        it 'sets refill_status to submitted when a valid Task exists' do
          VCR.use_cassette('unified_health_data/get_prescriptions_success') do
            prescriptions = service.get_prescriptions[:prescriptions]
            # Prescription 20848812135 has a Task with status='requested' and intent='order'
            submitted_prescription = prescriptions.find { |p| p.prescription_id == '20848812135' }

            expect(submitted_prescription.refill_status).to eq('submitted')
          end
        end

        it 'sets disp_status to Active: Submitted when a valid Task exists' do
          VCR.use_cassette('unified_health_data/get_prescriptions_success') do
            prescriptions = service.get_prescriptions[:prescriptions]
            # Prescription 20848812135 has a Task with status='requested' and intent='order'
            submitted_prescription = prescriptions.find { |p| p.prescription_id == '20848812135' }

            expect(submitted_prescription.disp_status).to eq('Active: Submitted')
          end
        end

        it 'sets refill_submit_date from Task executionPeriod.start' do
          VCR.use_cassette('unified_health_data/get_prescriptions_success') do
            prescriptions = service.get_prescriptions[:prescriptions]
            # Prescription 20848812135 has a Task with status='requested' and intent='order'
            submitted_prescription = prescriptions.find { |p| p.prescription_id == '20848812135' }

            expect(submitted_prescription.refill_submit_date).to be_a(String)
            expect(submitted_prescription.refill_submit_date).to eq('2026-03-20T18:59:55+00:00')
          end
        end

        it 'ignores Tasks with failed status' do
          VCR.use_cassette('unified_health_data/get_prescriptions_success') do
            prescriptions = service.get_prescriptions[:prescriptions]
            # Prescription 20848650695 has multiple Tasks but all have status='failed'
            failed_task_prescription = prescriptions.find { |p| p.prescription_id == '20848650695' }

            # Should NOT have refill_submit_date set from failed Tasks
            expect(failed_task_prescription.refill_submit_date).to be_nil
            # Should have normal active status, not submitted
            expect(failed_task_prescription.refill_status).to eq('active')
          end
        end

        it 'sets disp_status to Active (not Active: Submitted) when Tasks are failed' do
          VCR.use_cassette('unified_health_data/get_prescriptions_success') do
            prescriptions = service.get_prescriptions[:prescriptions]
            # Prescription 20848650695 has multiple Tasks but all have status='failed'
            failed_task_prescription = prescriptions.find { |p| p.prescription_id == '20848650695' }

            expect(failed_task_prescription.disp_status).to eq('Active')
          end
        end

        it 'does not affect prescriptions without any Tasks' do
          VCR.use_cassette('unified_health_data/get_prescriptions_success') do
            prescriptions = service.get_prescriptions[:prescriptions]
            # VistA prescription 26305871 should have no Task resources
            vista_prescription = prescriptions.find { |p| p.prescription_id == '26305871' }

            expect(vista_prescription.refill_status).to be_a(String)
          end
        end
      end

      # is_renewable attribute tests
      #
      # VCR Cassette Data Reference (unified_health_data/get_prescriptions_success):
      # ============================================================================
      # VistA Prescriptions:
      #   26305871: dispStatus='Active', isRenewable=true
      #   26305874: dispStatus='Discontinued', isRenewable=true
      #
      # Oracle Health Prescriptions:
      #   20848812135: status='active', intent='order', refills=2, containedCount=3 (completed dispenses)
      #                → NOT renewable (Gate 6: refills remaining > 0)
      #   20848639997: status='active', intent='plan', refills=0, containedCount=1 (no dispenses)
      #                → NOT renewable (Gate 3: no completed dispenses)
      #   20848863583: status='completed', intent='order', refills=0, containedCount=2
      #                → NOT renewable (Gate 1: status not active)
      #   20849028695: status='active', intent='order', refills=0, containedCount=2 (dispense status='in-progress')
      #                → NOT renewable (Gate 7: active processing)
      #
      # VCR Cassette Data Reference (unified_health_data/get_prescriptions_vista_only):
      # ================================================================================
      # VistA Prescriptions:
      #   25804852: dispStatus='Active: On Hold', isRenewable=false
      #   25804855: dispStatus='Expired', isRenewable=false
      #
      context 'is_renewable attribute' do
        context 'VistA prescriptions' do
          it 'computes is_renewable based on dispStatus and refillRemaining instead of upstream isRenewable' do
            VCR.use_cassette('unified_health_data/get_prescriptions_success') do
              prescriptions = service.get_prescriptions[:prescriptions]

              # 26305871: dispStatus='Active', refillRemaining=5, upstream isRenewable=true
              # Computed: false (has refills remaining)
              vista_prescription = prescriptions.find { |p| p.prescription_id == '26305871' }
              expect(vista_prescription.is_renewable).to be false

              # 26305874: dispStatus='Discontinued', refillRemaining=4, upstream isRenewable=true
              # Computed: false (discontinued is never renewable)
              discontinued_vista = prescriptions.find { |p| p.prescription_id == '26305874' }
              expect(discontinued_vista.is_renewable).to be false
            end
          end

          # NOTE: The vista_only cassette has OperationOutcome errors from Oracle Health,
          # which now raises UpstreamPartialFailure. The is_renewable: true case (tested above
          # with get_prescriptions_success cassette) provides coverage for VistA renewability pass-through.
          # If we need to test is_renewable: false specifically, we'd need a cassette with both
          # sources returning valid data but containing non-renewable prescriptions.
        end

        context 'Oracle Health prescriptions' do
          # Oracle Health renewability is computed client-side using 7 gate checks:
          # Gate 1: status == 'active'
          # Gate 2: VA prescription classification (not reportedBoolean, intent='order')
          # Gate 3: Has at least one completed MedicationDispense
          # Gate 4: Has validity period end date
          # Gate 5: Within 120-day renewal window from expiration
          # Gate 6: Refills exhausted OR prescription expired
          # Gate 7: No active processing (no in-progress/preparation dispenses)

          it 'returns false when refills remaining > 0 (Gate 6)' do
            VCR.use_cassette('unified_health_data/get_prescriptions_success') do
              prescriptions = service.get_prescriptions[:prescriptions]

              # 20848812135: status='active', intent='order', refills=2, has completed dispenses
              # Fails Gate 6: Still has 2 refills remaining, prescription not expired
              prescription = prescriptions.find { |p| p.prescription_id == '20848812135' }
              expect(prescription.is_renewable).to be false
            end
          end

          it 'returns false when no dispenses exist (Gate 3)' do
            VCR.use_cassette('unified_health_data/get_prescriptions_success') do
              prescriptions = service.get_prescriptions[:prescriptions]

              # 20848639997: status='active', intent='plan', refills=0
              # containedCount=1 but contains Encounter, not MedicationDispense
              # Fails Gate 3: No completed dispenses (never been dispensed)
              prescription = prescriptions.find { |p| p.prescription_id == '20848639997' }
              expect(prescription.is_renewable).to be false
            end
          end

          it 'returns false when status is not active (Gate 1)' do
            VCR.use_cassette('unified_health_data/get_prescriptions_success') do
              prescriptions = service.get_prescriptions[:prescriptions]

              # 20848863583: status='completed', intent='order', refills=0, has dispenses
              # Fails Gate 1: Status is 'completed', not 'active'
              prescription = prescriptions.find { |p| p.prescription_id == '20848863583' }
              expect(prescription.is_renewable).to be false
            end
          end
        end
      end

      context 'facility name extraction integration' do
        it 'uses cache when available and API when cache misses' do
          # Test cache hit scenario
          oh_stations.each do |station|
            allow(Rails.cache).to receive(:read)
              .with("uhd:facility_names:#{station}")
              .and_return('Cached Facility Name')
            allow(Rails.cache).to receive(:exist?)
              .with("uhd:facility_names:#{station}")
              .and_return(true)
          end

          VCR.use_cassette('unified_health_data/get_prescriptions_success') do
            prescriptions = service.get_prescriptions[:prescriptions]
            oracle_prescription = prescriptions.find { |p| p.prescription_id == '20848812135' }

            expect(oracle_prescription.facility_name).to eq('Cached Facility Name')
          end
        end

        it 'falls back to API when cache is empty' do
          oh_stations.each do |station|
            allow(Rails.cache).to receive(:read).with("uhd:facility_names:#{station}").and_return(nil)
            allow(Rails.cache).to receive(:exist?).with("uhd:facility_names:#{station}").and_return(false)
          end

          # Mock the Lighthouse API call
          mock_client = instance_double(Lighthouse::Facilities::V1::Client)
          mock_facility = double('facility', name: 'API Retrieved Facility')
          allow(Lighthouse::Facilities::V1::Client).to receive(:new).and_return(mock_client)
          allow(mock_client).to receive(:get_facilities).and_return([mock_facility])

          VCR.use_cassette('unified_health_data/get_prescriptions_success') do
            prescriptions = service.get_prescriptions[:prescriptions]
            oracle_prescription = prescriptions.find { |p| p.prescription_id == '20848812135' }

            expect(oracle_prescription.facility_name).to eq('API Retrieved Facility')
            expect(mock_client).to have_received(:get_facilities)
              .with(facilityIds: 'vha_668').at_least(:once)
          end
        end

        it 'handles API errors gracefully' do
          oh_stations.each do |station|
            allow(Rails.cache).to receive(:read).with("uhd:facility_names:#{station}").and_return(nil)
            allow(Rails.cache).to receive(:exist?).with("uhd:facility_names:#{station}").and_return(false)
          end
          allow(Rails.logger).to receive(:error)
          allow(StatsD).to receive(:increment)

          # Mock API to raise an error
          mock_client = instance_double(Lighthouse::Facilities::V1::Client)
          allow(Lighthouse::Facilities::V1::Client).to receive(:new).and_return(mock_client)
          allow(mock_client).to receive(:get_facilities).and_raise(StandardError, 'API unavailable')

          VCR.use_cassette('unified_health_data/get_prescriptions_success') do
            prescriptions = service.get_prescriptions[:prescriptions]
            oracle_prescription = prescriptions.find { |p| p.prescription_id == '20848812135' }

            expect(oracle_prescription.facility_name).to be_nil
            # Error is logged multiple times for different prescriptions with same station number
            expect(Rails.logger).to have_received(:error).with(
              'Failed to fetch facility name from API for station 668: API unavailable'
            ).at_least(:once)
            expect(StatsD).to have_received(:increment).with(
              'unified_health_data.facility_name_fallback.api_error'
            ).at_least(:once)
          end
        end
      end

      it 'logs prescription retrieval information' do
        allow(Rails.logger).to receive(:info)
        allow(StatsD).to receive(:gauge)
        allow(StatsD).to receive(:increment)

        VCR.use_cassette('unified_health_data/get_prescriptions_success') do
          service.get_prescriptions

          expect(Rails.logger).to have_received(:info).with(
            hash_including(
              message: 'UHD prescriptions retrieved',
              total_prescriptions: 73,
              current_filtering_applied: false,
              user_uuid: user.uuid,
              has_failed_stations: false,
              service: 'unified_health_data',
              by_disp_status: an_instance_of(Hash),
              by_refill_status: an_instance_of(Hash),
              suspended_refill_count: 0,
              suspended_disp_count: 0,
              status_not_available_count: an_instance_of(Integer),
              in_progress_count: satisfy { |n| n.is_a?(Integer) && n.positive? },
              active_count: satisfy { |n| n.is_a?(Integer) && n.positive? },
              blank_status_count: an_instance_of(Integer)
            )
          )
          expect(StatsD).to have_received(:gauge).with('api.uhd.prescriptions.index.total', 73)
          expect(StatsD).to have_received(:gauge)
            .with('api.uhd.prescriptions.index.in_progress', satisfy { |n| n.is_a?(Integer) && n.positive? })
          expect(StatsD).to have_received(:gauge).with('api.uhd.prescriptions.index.suspended_refill', 0)
          expect(StatsD).not_to have_received(:increment).with('api.uhd.prescriptions.index.with_suspended_refill')
        end
      end

      it 'logs lowercase status histogram keys for in-progress refill statuses' do
        allow(Rails.logger).to receive(:info)
        allow(StatsD).to receive(:gauge)
        allow(StatsD).to receive(:increment)

        # 'refillinprocess' comes from VistA prescriptions in the cassette (time-independent),
        # but 'submitted' comes from OH prescription 20848812135's 'requested' order-Task dated
        # 2026-03-20T18:59:55Z. Freeze time inside the always-enforced in-flight staleness window
        # so that OH task still resolves to 'submitted'; otherwise it is correctly dropped as stale
        # and the 'submitted'/'active: submitted' histogram keys disappear.
        travel_to(Time.zone.parse('2026-03-22 12:00:00 UTC')) do
          VCR.use_cassette('unified_health_data/get_prescriptions_success') do
            service.get_prescriptions

            expect(Rails.logger).to have_received(:info).with(
              hash_including(
                message: 'UHD prescriptions retrieved',
                by_refill_status: hash_including(
                  'refillinprocess' => satisfy(&:positive?),
                  'submitted' => satisfy(&:positive?)
                ),
                by_disp_status: hash_including(
                  'active: refill in process' => satisfy(&:positive?),
                  'active: submitted' => satisfy(&:positive?)
                ),
                in_progress_count: satisfy { |n| n.is_a?(Integer) && n.positive? }
              )
            )
          end
        end
      end

      it 'logs suspended counts when prescriptions have Suspended status' do
        allow(Rails.logger).to receive(:info)
        allow(StatsD).to receive(:gauge)
        allow(StatsD).to receive(:increment)

        result = {
          prescriptions: [
            UnifiedHealthData::Prescription.new(
              id: '1', prescription_id: '1', refill_status: 'suspended', disp_status: 'Suspended'
            ),
            UnifiedHealthData::Prescription.new(
              id: '2', prescription_id: '2', refill_status: 'active', disp_status: 'Active'
            )
          ],
          metadata: { has_failed_stations: false }
        }

        service.send(:log_prescriptions_result, result, false)

        expect(Rails.logger).to have_received(:info).with(
          hash_including(
            message: 'UHD prescriptions retrieved',
            total_prescriptions: 2,
            by_refill_status: { 'suspended' => 1, 'active' => 1 },
            by_disp_status: { 'suspended' => 1, 'active' => 1 },
            suspended_refill_count: 1,
            suspended_disp_count: 1
          )
        )
        expect(StatsD).to have_received(:gauge).with('api.uhd.prescriptions.index.suspended_refill', 1)
        expect(StatsD).to have_received(:increment).with('api.uhd.prescriptions.index.with_suspended_refill')
      end

      it 'fails open when summary logging raises' do
        allow(Rails.logger).to receive(:info).and_call_original
        allow(Rails.logger).to receive(:warn)
        allow(StatsD).to receive(:gauge)
        allow(StatsD).to receive(:increment)
        allow(service).to receive(:status_histogram).and_raise(StandardError, 'logger boom')

        VCR.use_cassette('unified_health_data/get_prescriptions_success') do
          result = service.get_prescriptions

          expect(result[:prescriptions].size).to eq(73)
          expect(Rails.logger).to have_received(:warn).with(
            'UHD prescriptions summary logging failed',
            hash_including(error_class: 'StandardError', error_message: 'logger boom')
          )
        end
      end
    end

    context 'with empty response', :vcr do
      it 'logs UHD prescriptions not found when no prescriptions are returned' do
        allow(Rails.logger).to receive(:info).and_call_original
        allow(StatsD).to receive(:gauge)
        allow(StatsD).to receive(:increment)

        VCR.use_cassette('unified_health_data/get_prescriptions_empty') do
          expect(Rails.logger).to receive(:info).with(
            hash_including(
              message: 'UHD prescriptions not found',
              total_prescriptions: 0,
              current_filtering_applied: false,
              user_uuid: user.uuid,
              has_failed_stations: false,
              service: 'unified_health_data',
              by_disp_status: {},
              by_refill_status: {},
              suspended_refill_count: 0,
              suspended_disp_count: 0,
              status_not_available_count: 0,
              in_progress_count: 0,
              active_count: 0,
              blank_status_count: 0
            )
          )

          result = service.get_prescriptions
          expect(result[:prescriptions]).to eq([])
          expect(result[:metadata]).to include(has_failed_stations: false)
          expect(StatsD).to have_received(:gauge).with('api.uhd.prescriptions.index.total', 0)
          expect(StatsD).not_to have_received(:increment).with('api.uhd.prescriptions.index.with_suspended_refill')
        end
      end
    end

    context 'with partial data (OperationOutcome errors)', :vcr do
      # The vista_only cassette contains OperationOutcome errors from Oracle Health (rate limiting).
      # The detector now raises UpstreamPartialFailure to prevent returning incomplete data.

      it 'raises UpstreamPartialFailure for VistA-only data when Oracle Health has errors' do
        VCR.use_cassette('unified_health_data/get_prescriptions_vista_only') do
          expect { service.get_prescriptions }.to raise_error(Common::Exceptions::UpstreamPartialFailure) do |error|
            expect(error.failed_sources).to include('oracle-health')
          end
        end
      end
    end

    context 'with Oracle Health only data (no errors)', :vcr do
      # The oracle_only cassette has valid Oracle Health data and empty VistA data (no OperationOutcome errors).
      # This tests that we can successfully parse responses when one source has no data.

      it 'handles Oracle Health-only data without errors' do
        VCR.use_cassette('unified_health_data/get_prescriptions_oracle_only') do
          prescriptions = service.get_prescriptions[:prescriptions]
          # Clinic-administered medications (category: outpatient, reportedBoolean: false, intent: order)
          # are excluded from the response
          expect(prescriptions.size).to eq(30)
          expect(prescriptions.map(&:prescription_id)).to contain_exactly(
            '15213978755', '15213978785', '15213998699', '15214166465', '15214174423',
            '15214174425', '15214174531', '15214174571', '15214174591', '15214275861',
            '15214282323', '15214282441', '15214303643', '15214535999', '15214661111',
            '15214777121', '15214834723', '15215020709', '15215098309', '15215168033',
            '15215168043', '15215488543', '15215721639', '15215979885', '15216187241',
            '15216346305', '15217281719', '15217757747', '15217757751', '15218955729'
          )
        end
      end
    end

    context 'metadata' do
      it 'always returns a hash with prescriptions and metadata' do
        VCR.use_cassette('unified_health_data/get_prescriptions_success') do
          result = service.get_prescriptions

          expect(result).to be_a(Hash)
          expect(result[:prescriptions]).to be_an(Array)
          expect(result[:metadata]).to have_key(:has_failed_stations)
          expect(result[:metadata][:has_failed_stations]).to be false
        end
      end

      it 'returns has_failed_stations: true when VistA has partial failure' do
        VCR.use_cassette('unified_health_data/get_prescriptions_vista_partial_failure') do
          result = service.get_prescriptions

          expect(result).to be_a(Hash)
          expect(result[:metadata][:has_failed_stations]).to be true
        end
      end
    end
  end

  describe '#refill_prescription' do
    before do
      allow_any_instance_of(UnifiedHealthData::Client).to receive(:refill_prescription_orders).and_call_original
    end

    context 'with valid refill request', :vcr do
      it 'submits refill requests and returns success/failure breakdown' do
        VCR.use_cassette('unified_health_data/refill_prescription_success') do
          orders = [
            { id: '20848650695', stationNumber: '668' },
            { id: '0000000000001', stationNumber: '570' }
          ]
          result = service.refill_prescription(orders)

          expect(result[:success]).to eq([{ id: '20848650695', status: 'Refill Submitted', station_number: '668' }])
          expect(result[:failed]).to eq([{ id: '0000000000001', error: 'Prescription is not Found',
                                           station_number: '570' }])
        end
      end

      # TODO: Not sure why this is failing
      #
      #   it 'formats request body correctly' do
      #     VCR.use_cassette('unified_health_data/refill_prescription_success') do
      #       orders = [
      #         { 'id' => '12345', 'stationNumber' => '570' },
      #         { 'id' => '67890', 'stationNumber' => '556' }
      #       ]
      #       expected_body = {
      #         patientId: user.icn,
      #         orders: [
      #           { orderId: '12345', stationNumber: '570' },
      #           { orderId: '67890', stationNumber: '556' }
      #         ]
      #       }.to_json

      #       client = UnifiedHealthData::Client.new
      #       expect(client).to receive(:refill_prescription_orders).with(expected_body)

      #       service.refill_prescription(orders)
      #     end
      #   end
    end

    context 'with service errors' do
      it 'handles network errors gracefully' do
        allow_any_instance_of(UnifiedHealthData::Client)
          .to receive(:refill_prescription_orders)
          .and_raise(StandardError.new('Network error'))

        orders = [{ id: '12345', stationNumber: '570' }]
        result = service.refill_prescription(orders)

        expect(result[:success]).to eq([])
        expect(result[:failed]).to contain_exactly(
          { id: '12345', error: 'Service unavailable', station_number: '570' }
        )
      end

      it 'logs error when refill fails' do
        allow_any_instance_of(UnifiedHealthData::Client)
          .to receive(:refill_prescription_orders)
          .and_raise(StandardError.new('API error'))
        allow(Rails.logger).to receive(:error)

        service.refill_prescription([{ id: '12345', stationNumber: '570' }])

        expect(Rails.logger).to have_received(:error).with('Error submitting prescription refill: API error')
      end
    end

    context 'with prescription not found', :vcr do
      it 'returns failed refill when prescription is not found' do
        VCR.use_cassette('unified_health_data/refill_prescription_empty') do
          result = service.refill_prescription([{ id: '21431810851', stationNumber: '663' }])

          expect(result[:success]).to eq([])
          expect(result[:failed]).to eq([{ id: '21431810851', error: 'Prescription is not Found',
                                           station_number: '663' }])
        end
      end
    end

    context 'parse_refill_response edge cases' do
      it 'always returns arrays for success and failed keys with nil response body' do
        response = double(body: nil)

        result = service.send(:parse_refill_response, response)

        expect(result).to have_key(:success)
        expect(result).to have_key(:failed)
        expect(result[:success]).to eq([])
        expect(result[:failed]).to eq([])
      end

      it 'always returns arrays for success and failed keys with non-array response body' do
        response = double(body: { error: 'Invalid format' })

        result = service.send(:parse_refill_response, response)

        expect(result).to have_key(:success)
        expect(result).to have_key(:failed)
        expect(result[:success]).to eq([])
        expect(result[:failed]).to eq([])
      end

      it 'always returns arrays for success and failed keys with empty array response' do
        response = double(body: [])

        result = service.send(:parse_refill_response, response)

        expect(result).to have_key(:success)
        expect(result).to have_key(:failed)
        expect(result[:success]).to eq([])
        expect(result[:failed]).to eq([])
      end

      it 'returns empty failed array when only successes exist' do
        response = double(body: [
                            { 'success' => true, 'orderId' => '123', 'message' => 'Success', 'stationNumber' => '570' }
                          ])

        result = service.send(:parse_refill_response, response)

        expect(result[:success]).to eq([
                                         { id: '123', status: 'Success', station_number: '570' }
                                       ])
        expect(result[:failed]).to eq([])
        expect(result[:failed]).to be_an(Array)
      end

      it 'returns empty success array when only failures exist' do
        response = double(body: [
                            { 'success' => false, 'orderId' => '456', 'message' => 'Failed', 'stationNumber' => '571' }
                          ])

        result = service.send(:parse_refill_response, response)

        expect(result[:success]).to eq([])
        expect(result[:success]).to be_an(Array)
        expect(result[:failed]).to eq([
                                        { id: '456', error: 'Failed', station_number: '571' }
                                      ])
      end
    end

    context 'extract_successful_refills' do
      it 'returns empty array when no successful refills exist' do
        refill_items = [
          { 'success' => false, 'orderId' => '123', 'message' => 'Failed', 'stationNumber' => '570' }
        ]

        result = service.send(:extract_successful_refills, refill_items)

        expect(result).to eq([])
      end

      it 'returns empty array when refill_items is empty' do
        result = service.send(:extract_successful_refills, [])

        expect(result).to eq([])
      end

      it 'extracts successful refills correctly' do
        refill_items = [
          { 'success' => true, 'orderId' => '123', 'message' => 'Success', 'stationNumber' => '570' },
          { 'success' => false, 'orderId' => '456', 'message' => 'Failed', 'stationNumber' => '571' }
        ]

        result = service.send(:extract_successful_refills, refill_items)

        expect(result).to eq([
                               { id: '123', status: 'Success', station_number: '570' }
                             ])
      end
    end

    context 'extract_failed_refills' do
      it 'returns empty array when no failed refills exist' do
        refill_items = [
          { 'success' => true, 'orderId' => '123', 'message' => 'Success', 'stationNumber' => '570' }
        ]

        result = service.send(:extract_failed_refills, refill_items)

        expect(result).to eq([])
      end

      it 'returns empty array when refill_items is empty' do
        result = service.send(:extract_failed_refills, [])

        expect(result).to eq([])
      end

      it 'extracts failed refills correctly' do
        refill_items = [
          { 'success' => true, 'orderId' => '123', 'message' => 'Success', 'stationNumber' => '570' },
          { 'success' => false, 'orderId' => '456', 'message' => 'Failed', 'stationNumber' => '571' }
        ]

        result = service.send(:extract_failed_refills, refill_items)

        expect(result).to eq([
                               { id: '456', error: 'Failed', station_number: '571' }
                             ])
      end
    end

    context 'validate_refill_response_count' do
      it 'does not raise error when counts match' do
        normalized_orders = [
          { id: '123', stationNumber: '570' },
          { id: '456', stationNumber: '571' }
        ]
        result = {
          success: [{ id: '123', status: 'submitted', station_number: '570' }],
          failed: [{ id: '456', error: 'Failed', station_number: '571' }]
        }

        expect do
          service.send(:validate_refill_response_count, normalized_orders, result)
        end.not_to raise_error
      end

      it 'raises error when response has fewer items than sent' do
        normalized_orders = [
          { id: '123', stationNumber: '570' },
          { id: '456', stationNumber: '571' },
          { id: '789', stationNumber: '572' }
        ]
        result = {
          success: [{ id: '123', status: 'submitted', station_number: '570' }],
          failed: [{ id: '456', error: 'Failed', station_number: '571' }]
        }

        allow(Rails.logger).to receive(:error)

        expect do
          service.send(:validate_refill_response_count, normalized_orders, result)
        end.to raise_error(Common::Exceptions::PrescriptionRefillResponseMismatch)

        expect(Rails.logger).to have_received(:error).with(
          'Refill response count mismatch: sent 3 orders, received 2 responses'
        )
      end

      it 'raises error when response has more items than sent' do
        normalized_orders = [
          { id: '123', stationNumber: '570' }
        ]
        result = {
          success: [{ id: '123', status: 'submitted', station_number: '570' }],
          failed: [{ id: '456', error: 'Failed', station_number: '571' }]
        }

        allow(Rails.logger).to receive(:error)

        expect do
          service.send(:validate_refill_response_count, normalized_orders, result)
        end.to raise_error(Common::Exceptions::PrescriptionRefillResponseMismatch)

        expect(Rails.logger).to have_received(:error).with(
          'Refill response count mismatch: sent 1 orders, received 2 responses'
        )
      end

      it 'raises error when no responses received for multiple orders' do
        normalized_orders = [
          { id: '123', stationNumber: '570' },
          { id: '456', stationNumber: '571' }
        ]
        result = {
          success: [],
          failed: []
        }

        allow(Rails.logger).to receive(:error)

        expect do
          service.send(:validate_refill_response_count, normalized_orders, result)
        end.to raise_error(Common::Exceptions::PrescriptionRefillResponseMismatch)

        expect(Rails.logger).to have_received(:error).with(
          'Refill response count mismatch: sent 2 orders, received 0 responses'
        )
      end

      it 'does not raise error when both orders and responses are empty' do
        normalized_orders = []
        result = {
          success: [],
          failed: []
        }

        expect do
          service.send(:validate_refill_response_count, normalized_orders, result)
        end.not_to raise_error
      end

      it 'handles all success responses correctly' do
        normalized_orders = [
          { id: '123', stationNumber: '570' },
          { id: '456', stationNumber: '571' }
        ]
        result = {
          success: [
            { id: '123', status: 'submitted', station_number: '570' },
            { id: '456', status: 'submitted', station_number: '571' }
          ],
          failed: []
        }

        expect do
          service.send(:validate_refill_response_count, normalized_orders, result)
        end.not_to raise_error
      end

      it 'handles all failed responses correctly' do
        normalized_orders = [
          { id: '123', stationNumber: '570' },
          { id: '456', stationNumber: '571' }
        ]
        result = {
          success: [],
          failed: [
            { id: '123', error: 'Failed', station_number: '570' },
            { id: '456', error: 'Failed', station_number: '571' }
          ]
        }

        expect do
          service.send(:validate_refill_response_count, normalized_orders, result)
        end.not_to raise_error
      end
    end
  end

  # ------------------------------------------------------------------
  # Private helper method specs
  # ------------------------------------------------------------------

  describe '#normalize_orders' do
    it 'returns empty array when orders is nil' do
      expect(service.send(:normalize_orders, nil)).to eq([])
    end

    it 'returns empty array when orders is empty' do
      expect(service.send(:normalize_orders, [])).to eq([])
    end

    it 'converts hash orders to indifferent access' do
      orders = [{ 'id' => '123', 'stationNumber' => '570' }]
      result = service.send(:normalize_orders, orders)
      expect(result.first[:id]).to eq('123')
      expect(result.first['id']).to eq('123')
    end

    it 'passes through objects that do not respond to with_indifferent_access' do
      struct_order = OpenStruct.new(id: '123', stationNumber: '570')
      orders = [struct_order]
      result = service.send(:normalize_orders, orders)
      expect(result.first).to eq(struct_order)
    end
  end

  describe '#build_refill_request_body' do
    it 'builds correct request body from normalized orders' do
      orders = [
        { id: '12345', stationNumber: '570' },
        { id: '67890', stationNumber: '556' }
      ]
      result = service.send(:build_refill_request_body, orders)

      expect(result[:patientId]).to eq(user.icn)
      expect(result[:orders]).to eq([
                                      { orderId: '12345', stationNumber: '570' },
                                      { orderId: '67890', stationNumber: '556' }
                                    ])
    end

    it 'converts ids and station numbers to strings' do
      orders = [{ id: 12_345, stationNumber: 570 }]
      result = service.send(:build_refill_request_body, orders)

      expect(result[:orders].first[:orderId]).to eq('12345')
      expect(result[:orders].first[:stationNumber]).to eq('570')
    end

    it 'handles empty orders' do
      result = service.send(:build_refill_request_body, [])

      expect(result[:patientId]).to eq(user.icn)
      expect(result[:orders]).to eq([])
    end
  end

  describe '#build_error_response' do
    it 'builds error response with Service unavailable for each order' do
      orders = [
        { id: '123', stationNumber: '570' },
        { id: '456', stationNumber: '556' }
      ]
      result = service.send(:build_error_response, orders)

      expect(result[:success]).to eq([])
      expect(result[:failed].size).to eq(2)
      expect(result[:failed].first).to eq({ id: '123', error: 'Service unavailable', station_number: '570' })
      expect(result[:failed].last).to eq({ id: '456', error: 'Service unavailable', station_number: '556' })
    end

    it 'returns empty failed array for empty orders' do
      result = service.send(:build_error_response, [])

      expect(result[:success]).to eq([])
      expect(result[:failed]).to eq([])
    end
  end
end
