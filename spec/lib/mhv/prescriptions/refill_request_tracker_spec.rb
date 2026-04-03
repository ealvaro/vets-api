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
end
