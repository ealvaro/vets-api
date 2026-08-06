# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EventBusGateway::Constants do
  include ActiveSupport::Testing::TimeHelpers

  describe '.sms_blackout_period?' do
    let(:eastern) { ActiveSupport::TimeZone['Eastern Time (US & Canada)'] }

    context 'during blackout window' do
      it 'returns true at 9:00 PM Eastern' do
        travel_to eastern.local(2025, 1, 15, 21, 0, 0) do
          expect(described_class.sms_blackout_period?).to be true
        end
      end

      it 'returns true at 11:59 PM Eastern' do
        travel_to eastern.local(2025, 1, 15, 23, 59, 0) do
          expect(described_class.sms_blackout_period?).to be true
        end
      end

      it 'returns true at midnight Eastern' do
        travel_to eastern.local(2025, 1, 16, 0, 0, 0) do
          expect(described_class.sms_blackout_period?).to be true
        end
      end

      it 'returns true at 8:59 AM Eastern' do
        travel_to eastern.local(2025, 1, 16, 8, 59, 0) do
          expect(described_class.sms_blackout_period?).to be true
        end
      end
    end

    context 'outside blackout window' do
      it 'returns false at 9:00 AM Eastern' do
        travel_to eastern.local(2025, 1, 15, 9, 0, 0) do
          expect(described_class.sms_blackout_period?).to be false
        end
      end

      it 'returns false at 12:00 PM Eastern' do
        travel_to eastern.local(2025, 1, 15, 12, 0, 0) do
          expect(described_class.sms_blackout_period?).to be false
        end
      end

      it 'returns false at 8:59 PM Eastern' do
        travel_to eastern.local(2025, 1, 15, 20, 59, 0) do
          expect(described_class.sms_blackout_period?).to be false
        end
      end
    end

    context 'daylight saving time' do
      it 'returns true at 9:00 PM EDT (summer)' do
        travel_to eastern.local(2025, 7, 15, 21, 0, 0) do
          expect(described_class.sms_blackout_period?).to be true
        end
      end

      it 'returns false at 9:00 AM EDT (summer)' do
        travel_to eastern.local(2025, 7, 15, 9, 0, 0) do
          expect(described_class.sms_blackout_period?).to be false
        end
      end

      it 'returns true at 9:00 PM EST (winter)' do
        travel_to eastern.local(2025, 1, 15, 21, 0, 0) do
          expect(described_class.sms_blackout_period?).to be true
        end
      end

      it 'returns false at 9:00 AM EST (winter)' do
        travel_to eastern.local(2025, 1, 15, 9, 0, 0) do
          expect(described_class.sms_blackout_period?).to be false
        end
      end
    end
  end

  describe '.compute_blackout_defer_slot' do
    let(:window) { described_class.sms_blackout_defer_window_minutes }

    it 'maps the same identifier to the same slot across calls' do
      slot = described_class.compute_blackout_defer_slot('foo-bar-baz')
      expect(described_class.compute_blackout_defer_slot('foo-bar-baz')).to eq(slot)
    end

    it 'returns a value in [0, window_minutes)' do
      100.times do |i|
        slot = described_class.compute_blackout_defer_slot("id-#{i}")
        expect(slot).to be_between(0, window - 1)
      end
    end

    it 'honors an explicit window_minutes argument' do
      slot = described_class.compute_blackout_defer_slot('anything', 60)
      expect(slot).to be_between(0, 59)
    end
  end

  describe '.next_blackout_defer_time' do
    let(:eastern) { ActiveSupport::TimeZone['Eastern Time (US & Canada)'] }

    it 'lands inside the 9 AM–noon Eastern window when called during overnight blackout' do
      travel_to eastern.local(2025, 1, 16, 2, 0, 0) do
        result = described_class.next_blackout_defer_time('foo').in_time_zone(eastern)
        expect(result).to be >= eastern.local(2025, 1, 16, 9, 0, 0)
        expect(result).to be <  eastern.local(2025, 1, 16, 12, 0, 0)
      end
    end

    it 'rolls to tomorrow when called late at night (before midnight)' do
      travel_to eastern.local(2025, 1, 15, 23, 0, 0) do
        result = described_class.next_blackout_defer_time('foo').in_time_zone(eastern)
        expect(result).to be >= eastern.local(2025, 1, 16, 9, 0, 0)
        expect(result).to be <  eastern.local(2025, 1, 16, 12, 0, 0)
      end
    end

    it 'lands in the same-day window when called early-morning before 9 AM' do
      travel_to eastern.local(2025, 1, 16, 6, 30, 0) do
        result = described_class.next_blackout_defer_time('foo').in_time_zone(eastern)
        expect(result).to be >= eastern.local(2025, 1, 16, 9, 0, 0)
        expect(result).to be <  eastern.local(2025, 1, 16, 12, 0, 0)
      end
    end
  end

  describe 'gated send tuning' do
    let(:gated_send) { Settings.vanotify.services.benefits_management_tools.gated_send }

    describe '.gated_send_recheck_interval_minutes' do
      it 'reads the configured value' do
        allow(gated_send).to receive(:recheck_interval_minutes).and_return(30)
        expect(described_class.gated_send_recheck_interval_minutes).to eq(30)
      end

      it 'falls back to the default when unset or non-positive' do
        allow(gated_send).to receive(:recheck_interval_minutes).and_return(nil)
        expect(described_class.gated_send_recheck_interval_minutes)
          .to eq(described_class::GATED_SEND_DEFAULT_RECHECK_INTERVAL_MINUTES)
      end
    end

    describe '.gated_send_max_recheck_attempts' do
      it 'reads the configured value' do
        allow(gated_send).to receive(:max_recheck_attempts).and_return(2)
        expect(described_class.gated_send_max_recheck_attempts).to eq(2)
      end

      it 'falls back to the default when unset or non-positive' do
        allow(gated_send).to receive(:max_recheck_attempts).and_return(0)
        expect(described_class.gated_send_max_recheck_attempts)
          .to eq(described_class::GATED_SEND_DEFAULT_MAX_RECHECK_ATTEMPTS)
      end
    end

    describe '.gated_send_fallback_send_anyway?' do
      it 'casts a configured string to a boolean' do
        allow(gated_send).to receive(:fallback_send_anyway).and_return('false')
        expect(described_class.gated_send_fallback_send_anyway?).to be(false)
      end

      it 'defaults to send-anyway when unset' do
        allow(gated_send).to receive(:fallback_send_anyway).and_return(nil)
        expect(described_class.gated_send_fallback_send_anyway?)
          .to eq(described_class::GATED_SEND_DEFAULT_FALLBACK_SEND_ANYWAY)
      end
    end
  end
end
