# frozen_string_literal: true

require 'rails_helper'
require 'unified_health_data/models/prescription'
require 'unified_health_data/adapters/prescriptions_adapter'

# Regression coverage for the "Refill in Process" reclassification performed by
# PrescriptionsAdapter#apply_awaiting_tracking_logic (gated by
# mhv_medications_management_improvements).
#
# Bug: a freshly staged, still-refillable titratable prescription was surfaced as
# refill_status "refillinprocess" even though no refill was ever requested and nothing was
# in process. Root cause: awaiting_tracking? reclassified ANY 'Active' med dispensed within
# the 15-day window with no tracking, using only the top-level dispensedDate of the initial
# fill. Fix: only a fill backed by an actual *refill* dispense can be "awaiting tracking".
# The check is source-aware because the two EHRs model dispenses differently: VistA dispenses
# are rxRFRecords (refills only, so an initial fill has none), while an OH initial fill is
# itself a completed MedicationDispense, so OH needs MORE than one completed dispense to
# indicate a refill (mirrors OracleHealthRefillHelper's `completed_dispenses - 1` math).
#
# is_refillable is deliberately NOT the discriminator: a prescription with refills remaining
# can report isRefillable true while an already-requested refill is being filled/shipped, so
# the two scenarios below differ ONLY by the presence of a dispense record while both are
# refillable.
RSpec.describe UnifiedHealthData::Adapters::PrescriptionsAdapter, type: :model do
  subject(:adapter) { described_class.new(user) }

  let(:user) { build(:user, :loa3, icn: '1000123456V123456') }

  # Frozen so a dispense dated "today" falls inside the 15-day window.
  let(:frozen_time) { Time.zone.parse('2026-07-28 12:00:00') }

  # Base: active VistA titratable, dispensed today, no tracking, no refill submitted.
  let(:base_medication_hash) do
    {
      'refillStatus' => 'active',
      'refillSubmitDate' => nil,
      'refillDate' => 'Tue, 28 Jul 2026 00:00:00 EDT',
      'refillRemaining' => 11,
      'facilityApiName' => 'Dayton Medical Center',
      'isRefillable' => true,
      'isTrackable' => false,
      'prescriptionId' => 29_511_985,
      'sig' => 'TAKE ONE TABLET BY MOUTH DAILY FOR 14 DAYS, THEN TAKE TWO TABLETS DAILY',
      'orderedDate' => 'Tue, 28 Jul 2026 00:00:00 EDT',
      'quantity' => '60',
      'expirationDate' => 'Thu, 29 Jul 2027 00:00:00 EDT',
      'prescriptionNumber' => '2721495',
      'prescriptionName' => 'METOPROLOL SUCCINATE 100MG SA TAB',
      'dispensedDate' => 'Tue, 28 Jul 2026 00:00:00 EDT',
      'stationNumber' => '989',
      'id' => 29_511_985,
      'dispStatus' => 'Active',
      'prescriptionSource' => 'RX',
      'dataSourceSystem' => 'VISTA',
      'isRenewable' => false,
      'trackingList' => nil,
      'rxRFRecords' => nil,
      'tracking' => false
    }
  end

  def base_medication(overrides = {})
    base_medication_hash.merge(overrides)
  end

  # A refill/dispense record dispensed `days_ago` days ago (drives dispenses / sorted date).
  def refill_record(days_ago)
    {
      'rfRecord' => [
        {
          'refillStatus' => 'active',
          'dispensedDate' => (frozen_time - days_ago.days).strftime('%a, %d %b %Y 00:00:00 EDT'),
          'prescriptionName' => 'METOPROLOL SUCCINATE 100MG SA TAB',
          'id' => 1001,
          'prescriptionNumber' => '2721495'
        }
      ]
    }
  end

  # A refill/dispense record dispensed on an explicit calendar date (for time-travel tests
  # whose expectations must not shift with the frozen "now").
  def refill_record_on(date_str)
    {
      'rfRecord' => [
        {
          'refillStatus' => 'active',
          'dispensedDate' => Date.parse(date_str).strftime('%a, %d %b %Y 00:00:00 EDT'),
          'prescriptionName' => 'METOPROLOL SUCCINATE 100MG SA TAB',
          'id' => 1001,
          'prescriptionNumber' => '2721495'
        }
      ]
    }
  end

  # A shipped tracking entry carrying a completion date (drives recent_tracking?).
  def tracking_list(days_ago)
    {
      'tracking' => [
        {
          'completeDateTime' => (frozen_time - days_ago.days).strftime('%a, %d %b %Y 00:00:00 EDT'),
          'trackingNumber' => '1Z999',
          'carrier' => 'USPS'
        }
      ]
    }
  end

  def envelope(medication)
    {
      'vista' => { 'medicationList' => { 'medication' => [medication] } },
      'oracle-health' => {}
    }
  end

  def parse_first(medication)
    adapter.parse(envelope(medication))[:prescriptions].first
  end

  around { |example| Timecop.freeze(frozen_time) { example.run } }

  before do
    allow(Flipper).to receive(:enabled?).and_call_original
    allow(Flipper).to receive(:enabled?)
      .with(:mhv_medications_display_pending_meds, user).and_return(false)
  end

  context 'when mhv_medications_management_improvements is ON' do
    before do
      allow(Flipper).to receive(:enabled?)
        .with(:mhv_medications_management_improvements, user).and_return(true)
    end

    context 'a freshly staged initial fill with no refill/dispense record' do
      it 'stays Active and is NOT reclassified to Refill in Process' do
        rx = parse_first(base_medication)

        expect(rx.refill_status).to eq('active')
        expect(rx.disp_status).to eq('Active')
        expect(rx.is_awaiting_tracking).to be false
        expect(rx.is_refillable).to be true
      end

      it 'reports awaiting_tracking? false because there is no dispense record' do
        rx = UnifiedHealthData::Adapters::VistaPrescriptionAdapter.new.parse(base_medication)

        expect(rx.dispenses).to be_blank
        expect(adapter.send(:awaiting_tracking?, rx)).to be false
      end
    end

    context 'an initial fill of a non-refillable (one-time) med, no dispense record' do
      it 'stays Active' do
        rx = parse_first(base_medication('isRefillable' => false, 'refillRemaining' => 0))

        expect(rx.refill_status).to eq('active')
        expect(rx.disp_status).to eq('Active')
        expect(rx.is_awaiting_tracking).to be false
      end
    end

    context 'a genuine refill fill awaiting shipment (dispense record present, no tracking)' do
      # Same refillable state as the staged initial fill above; differs ONLY by having a real
      # refill/dispense record.
      it 'IS reclassified to Refill in Process (feature preserved)' do
        rx = parse_first(base_medication('rxRFRecords' => refill_record(3)))

        expect(rx.refill_status).to eq('refillinprocess')
        expect(rx.disp_status).to eq('Active: Refill in Process')
        expect(rx.is_awaiting_tracking).to be true
        expect(rx.is_trackable).to be false
      end

      # A prescription can be BOTH is_refillable true
      # AND Active: Refill in Process at the same time. This is intentional and asserted
      # explicitly so it is not treated as a bug: a titratable/partial-fill med keeps refills
      # remaining (isRefillable true) even while the most recent refill is being filled/shipped.
      # is_refillable is upstream-owned and is deliberately NOT used to gate the in-process
      # state, so awaiting_tracking? does not (and should not) clear it.
      it 'keeps is_refillable true while Active: Refill in Process (intended, not a bug)' do
        rx = parse_first(base_medication('isRefillable' => true, 'rxRFRecords' => refill_record(3)))

        expect(rx.disp_status).to eq('Active: Refill in Process')
        expect(rx.is_refillable).to be true
      end

      it 'is NOT reclassified when the refill dispense is beyond the 15-day window' do
        rx = parse_first(base_medication('rxRFRecords' => refill_record(20)))

        expect(rx.refill_status).to eq('active')
        expect(rx.disp_status).to eq('Active')
        expect(rx.is_awaiting_tracking).to be false
      end
    end

    context 'the 15-day window boundary (date-granularity comparison)' do
      # Comparison is `dispensed_date.to_date >= 15.days.ago.to_date`, so it is inclusive at the
      # 15-day edge and insensitive to time-of-day/DST because time is frozen and both sides are
      # reduced to dates.
      it 'reclassifies a refill dispensed exactly 15 days ago (inclusive)' do
        rx = parse_first(base_medication('rxRFRecords' => refill_record(15)))

        expect(rx.disp_status).to eq('Active: Refill in Process')
        expect(rx.is_awaiting_tracking).to be true
      end

      it 'leaves a refill dispensed 16 days ago as Active (past the window)' do
        rx = parse_first(base_medication('rxRFRecords' => refill_record(16)))

        expect(rx.disp_status).to eq('Active')
        expect(rx.is_awaiting_tracking).to be false
      end
    end

    context 'time-travel: the in-process state exits after the 15-day window' do
      # A refill dispensed 2026-07-16. Prove the negative exit: in-process while within the
      # window, then back to Active once the clock passes the window edge (2026-07-31).
      let(:med) { base_medication('rxRFRecords' => refill_record_on('2026-07-16')) }

      it 'is Refill in Process at 2026-07-28 (12 days after the dispense)' do
        rx = parse_first(med)

        expect(rx.disp_status).to eq('Active: Refill in Process')
        expect(rx.is_awaiting_tracking).to be true
      end

      it 'reverts to Active at 2026-08-01 (16 days after the dispense)' do
        Timecop.travel(Time.zone.parse('2026-08-01 12:00:00')) do
          rx = parse_first(med)

          expect(rx.disp_status).to eq('Active')
          expect(rx.is_awaiting_tracking).to be false
        end
      end
    end

    context 'a completed refill cycle dispensed outside the window' do
      # awaiting_tracking? is governed purely by the dispense signal + 15-day window, so once
      # the dispense falls outside the window the fill exits to Active even though a stale
      # submit date remains.
      it 'stays Active once the completed cycle is outside the window' do
        med = base_medication(
          'refillSubmitDate' => (frozen_time - 40.days).utc.iso8601(3),
          'rxRFRecords' => refill_record(20)
        )
        rx = parse_first(med)

        expect(rx.disp_status).to eq('Active')
        expect(rx.is_awaiting_tracking).to be false
      end
    end

    context 'a refill dispensed within the window but already shipped (tracking present)' do
      # recent_tracking? excludes a fill that already has a tracking entry with a completion
      # date: it has shipped, so it is not "awaiting tracking".
      it 'is not reclassified to Refill in Process' do
        rx = parse_first(
          base_medication('rxRFRecords' => refill_record(3), 'trackingList' => tracking_list(2))
        )

        expect(rx.disp_status).not_to eq('Active: Refill in Process')
        expect(rx.is_awaiting_tracking).to be false
      end
    end

    context 'a non-Active prescription (discontinued/expired/hold)' do
      it 'is left untouched even with a recent dispense record' do
        rx = parse_first(
          base_medication(
            'refillStatus' => 'discontinued',
            'dispStatus' => 'Discontinued',
            'rxRFRecords' => refill_record(3)
          )
        )

        expect(rx.refill_status).to eq('discontinued')
        expect(rx.disp_status).to eq('Discontinued')
        expect(rx.is_awaiting_tracking).to be false
      end
    end

    context 'OH-sourced prescriptions (initial fill is itself a MedicationDispense)' do
      # OH builds dispenses from every contained MedicationDispense, and the initial fill is
      # itself a completed MedicationDispense. So a refill exists only when MORE than one
      # completed dispense is present, mirroring OracleHealthRefillHelper's
      # `completed_dispenses - 1` refills-used math. A bare dispenses.blank? check would be a
      # no-op for OH and mislabel initial fills — the bug @Adrian-Rollett flagged on #29654.
      def oh_rx(dispenses:)
        UnifiedHealthData::Prescription.new(
          id: '12345',
          disp_status: 'Active',
          source_ehr: UnifiedHealthData::Prescription::SOURCE_EHR_ORACLE_HEALTH,
          sorted_dispensed_date: 3.days.ago.to_date.to_s,
          dispensed_date: nil,
          dispenses:,
          tracking: []
        )
      end

      it 'is NOT awaiting tracking for an OH initial fill (exactly one completed dispense)' do
        rx = oh_rx(dispenses: [{ status: 'completed', when_handed_over: 3.days.ago.to_date.to_s }])

        expect(adapter.send(:awaiting_tracking?, rx)).to be false
      end

      it 'is awaiting tracking for an OH refill (initial fill + one completed refill dispense)' do
        rx = oh_rx(dispenses: [
                     { status: 'completed', when_handed_over: 20.days.ago.to_date.to_s },
                     { status: 'completed', when_handed_over: 3.days.ago.to_date.to_s }
                   ])

        expect(adapter.send(:awaiting_tracking?, rx)).to be true
      end

      it 'is NOT awaiting tracking when the second dispense is not yet completed' do
        rx = oh_rx(dispenses: [
                     { status: 'completed', when_handed_over: 20.days.ago.to_date.to_s },
                     { status: 'in-progress', when_handed_over: nil }
                   ])

        expect(adapter.send(:awaiting_tracking?, rx)).to be false
      end

      it 'does not count a voided (entered-in-error) dispense as a refill' do
        rx = oh_rx(dispenses: [
                     { status: 'completed', when_handed_over: 20.days.ago.to_date.to_s },
                     { status: 'entered-in-error', when_handed_over: 3.days.ago.to_date.to_s }
                   ])

        expect(adapter.send(:awaiting_tracking?, rx)).to be false
      end

      it 'is NOT awaiting tracking when the OH record has no dispenses' do
        rx = oh_rx(dispenses: [])

        expect(adapter.send(:awaiting_tracking?, rx)).to be false
      end
    end

    context 'a med that already reports refillinprocess upstream' do
      it 'passes through unchanged' do
        rx = parse_first(
          base_medication('refillStatus' => 'refillinprocess', 'dispStatus' => 'Active: Refill in Process')
        )

        expect(rx.refill_status).to eq('refillinprocess')
        expect(rx.disp_status).to eq('Active: Refill in Process')
      end
    end
  end

  context 'when mhv_medications_management_improvements is OFF' do
    before do
      allow(Flipper).to receive(:enabled?)
        .with(:mhv_medications_management_improvements, user).and_return(false)
    end

    it 'passes upstream status through unchanged for the staged initial fill' do
      rx = parse_first(base_medication)

      expect(rx.refill_status).to eq('active')
      expect(rx.disp_status).to eq('Active')
    end

    it 'does not reclassify even a genuine refill fill (flag gated)' do
      rx = parse_first(base_medication('rxRFRecords' => refill_record(3)))

      expect(rx.refill_status).to eq('active')
      expect(rx.disp_status).to eq('Active')
    end
  end
end
