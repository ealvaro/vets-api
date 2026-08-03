# frozen_string_literal: true

require 'rails_helper'
require 'mhv/prescriptions/refill_request_tracker'
require 'unified_health_data/models/prescription'

RSpec.describe MHV::Prescriptions::RefillRequestTracker do
  subject(:tracker) { described_class.new(user, cache:, ttl: 10.minutes) }

  let(:user) { build(:user, icn: '1234567890V123456') }
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }
  let(:order) { { 'stationNumber' => '570', 'id' => '12345' } }

  describe '#claim_orders' do
    it 'claims new orders and blocks duplicates' do
      claimed_orders, duplicate_failures = tracker.claim_orders([order])
      expect(claimed_orders).to eq([order])
      expect(duplicate_failures).to eq([])

      claimed_orders, duplicate_failures = tracker.claim_orders([order])
      expect(claimed_orders).to eq([])
      expect(duplicate_failures).to eq([
                                         {
                                           id: '12345',
                                           error: described_class::DUPLICATE_REFILL_ERROR,
                                           station_number: '570'
                                         }
                                       ])
    end
  end

  describe '#release_orders' do
    it 'allows re-claiming after release' do
      tracker.claim_orders([order])
      tracker.release_orders([{ id: '12345', station_number: '570' }])

      claimed_orders, duplicate_failures = tracker.claim_orders([order])
      expect(claimed_orders).to eq([order])
      expect(duplicate_failures).to eq([])
    end
  end

  describe '#apply_submitted_state!' do
    let(:prescription) do
      UnifiedHealthData::Prescription.new(
        id: '12345',
        station_number: '570',
        refill_remaining: 3,
        is_refillable: true,
        disp_status: 'Active',
        refill_status: 'active'
      )
    end

    it 'marks claimed prescriptions as in progress and decrements refill count once' do
      tracker.claim_orders([order])

      tracker.apply_submitted_state!([prescription], in_progress_status: 'In progress')

      expect(prescription.disp_status).to eq('In progress')
      expect(prescription.refill_status).to eq('submitted')
      expect(prescription.is_refillable).to be(false)
      expect(prescription.refill_remaining).to eq(2)
      expect(prescription.refill_submit_date).to be_present
    end

    it 'does not decrement refill count when prescription is already submitted upstream' do
      prescription.refill_remaining = 2
      prescription.refill_status = 'submitted'
      prescription.is_refillable = false
      prescription.refill_submit_date = 1.day.ago.iso8601
      tracker.claim_orders([order])

      tracker.apply_submitted_state!([prescription], in_progress_status: 'In progress')

      expect(prescription.disp_status).to eq('In progress')
      expect(prescription.refill_status).to eq('submitted')
      expect(prescription.is_refillable).to be(false)
      expect(prescription.refill_remaining).to eq(2)
      expect(prescription.refill_submit_date).to be_present
    end

    it 'does not mutate prescriptions without active claims' do
      tracker.apply_submitted_state!([prescription], in_progress_status: 'In progress')

      expect(prescription.disp_status).to eq('Active')
      expect(prescription.refill_remaining).to eq(3)
      expect(prescription.is_refillable).to be(true)
      expect(prescription.refill_submit_date).to be_nil
    end
  end

  describe 'cache failure resilience' do
    context 'when cache write fails' do
      it 'fails open (treats order as claimed and allows upload) and logs warning' do
        allow(cache).to receive(:write).and_raise(Redis::ConnectionError.new('Connection refused'))
        allow(Rails.logger).to receive(:warn)

        claimed_orders, duplicate_failures = tracker.claim_orders([order])

        expect(claimed_orders).to eq([order])
        expect(duplicate_failures).to eq([])
        expect(Rails.logger).to have_received(:warn).with(
          'RefillRequestTracker cache write failed (failing open): Redis::ConnectionError Connection refused'
        )
      end
    end

    context 'when cache read fails' do
      it 'fails open (assumes no orders claimed, blocks nothing) and logs warning' do
        tracker.claim_orders([order])
        cache_key = tracker.send(:cache_key_for_order, order)

        allow(cache).to receive(:read_multi).and_raise(Redis::TimeoutError.new('Timeout'))
        allow(Rails.logger).to receive(:warn)

        claimed_keys = tracker.send(:claimed_cache_keys, [cache_key])

        expect(claimed_keys).to eq([])
        expect(Rails.logger).to have_received(:warn).with(
          'RefillRequestTracker cache read failed (failing open): Redis::TimeoutError Timeout'
        )
      end
    end

    context 'when cache delete fails' do
      it 'logs warning but does not raise' do
        tracker.claim_orders([order])
        allow(cache).to receive(:delete).and_raise(Redis::ConnectionError.new('Connection lost'))
        allow(Rails.logger).to receive(:warn)

        expect do
          tracker.release_orders([{ id: '12345', station_number: '570' }])
        end.not_to raise_error

        expect(Rails.logger).to have_received(:warn).with(
          'RefillRequestTracker cache delete failed: Redis::ConnectionError Connection lost'
        )
      end
    end
  end

  # RC5 CHARACTERIZATION: the refill "badge" that keeps a just-submitted
  # prescription showing as in-progress is backed by a cache entry with a fixed
  # TTL (10 min here, 15 min in prod). Once that TTL elapses the duplicate block
  # disappears and the prescription silently reverts to plain upstream 'Active'
  # until upstream itself reflects the refill. These tests assert the CURRENT
  # (buggy) time-bomb behavior; they must PASS.
  describe 'claim TTL expiry (RC5)' do
    include ActiveSupport::Testing::TimeHelpers

    it 'holds the badge before the TTL elapses' do
      # DESIRED: the badge stays until upstream confirms the refill.
      # CURRENT: the badge is held only while the cache key lives, which is fine
      # inside the window (this asserts the block is genuinely active at 9 min).
      tracker.claim_orders([order])

      travel(9.minutes) do
        claimed_orders, duplicate_failures = tracker.claim_orders([order])
        expect(claimed_orders).to eq([])
        expect(duplicate_failures).not_to be_empty
      end
    end

    it 'badge expires after the TTL, allowing re-claim (the transient revert mechanism)' do
      # RC5 CHARACTERIZATION: once the 10-min badge (prod default 15 min) expires,
      # the duplicate block is gone and the prescription reverts to plain upstream
      # 'Active' until upstream reflects the refill.
      tracker.claim_orders([order])

      travel(11.minutes) do
        claimed_orders, duplicate_failures = tracker.claim_orders([order])
        expect(claimed_orders).to eq([order])
        expect(duplicate_failures).to eq([])
      end
    end
  end

  # I2: the claim TTL (dup-guard lifetime) is now Settings-tunable rather than a
  # hardcoded 15-minute cliff. The constructor default reads the configured value
  # with safe coercion, falling back to DEFAULT_CLAIM_TTL for missing/blank/zero/
  # non-numeric settings (config gem may deliver nil/String/Integer).
  describe 'configurable TTL (I2)' do
    include ActiveSupport::Testing::TimeHelpers

    def stub_ttl_setting(value)
      allow(Settings).to receive(:dig).and_call_original
      allow(Settings).to receive(:dig).with(:mhv, :rx, :refill_claim_ttl_seconds).and_return(value)
    end

    it 'uses the Settings-configured TTL for the constructor default' do
      stub_ttl_setting(120)
      base_time = Time.current
      default_tracker = described_class.new(user, cache:)

      travel_to(base_time) do
        default_tracker.claim_orders([order])
      end

      # Still blocked just before the configured 2-minute TTL elapses.
      travel_to(base_time + 1.minute) do
        claimed_orders, duplicate_failures = default_tracker.claim_orders([order])
        expect(claimed_orders).to eq([])
        expect(duplicate_failures).not_to be_empty
      end

      # Re-claimable just past the configured 2-minute TTL boundary.
      travel_to(base_time + 2.minutes + 1.second) do
        claimed_orders, = default_tracker.claim_orders([order])
        expect(claimed_orders).to eq([order])
      end
    end

    it 'falls back to DEFAULT_CLAIM_TTL when the setting is missing' do
      stub_ttl_setting(nil)
      expect(described_class.configured_ttl).to eq(15.minutes)
    end

    it 'falls back to DEFAULT_CLAIM_TTL when the setting is blank' do
      stub_ttl_setting('')
      expect(described_class.configured_ttl).to eq(15.minutes)
    end

    it 'falls back to DEFAULT_CLAIM_TTL when the setting is zero' do
      stub_ttl_setting(0)
      expect(described_class.configured_ttl).to eq(15.minutes)
    end

    it 'falls back to DEFAULT_CLAIM_TTL when the setting is non-numeric' do
      stub_ttl_setting('abc')
      expect(described_class.configured_ttl).to eq(15.minutes)
    end
  end
end
