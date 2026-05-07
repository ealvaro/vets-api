# frozen_string_literal: true

require 'rails_helper'
require 'unified_health_data/adapters/date_time_helpers'

describe UnifiedHealthData::Adapters::DateTimeHelpers do
  subject { helper_class.new }

  let(:helper_class) do
    Class.new do
      include UnifiedHealthData::Adapters::DateTimeHelpers

      # Stub log_adapter since it's defined in a separate concern
      def log_adapter(level, _structured_opts, fallback_message, fallback_opts = {})
        Rails.logger.public_send(level, fallback_message, fallback_opts)
      end
    end
  end

  describe '#parse_date_or_epoch' do
    it 'parses a valid ISO 8601 date string' do
      result = subject.parse_date_or_epoch('2025-06-24T21:05:53.000Z')
      expect(result).to be_a(Time)
      expect(result.year).to eq(2025)
      expect(result.month).to eq(6)
      expect(result.day).to eq(24)
    end

    it 'returns epoch when date_string is nil' do
      result = subject.parse_date_or_epoch(nil)
      expect(result).to eq(Time.zone.at(0))
    end

    it 'returns epoch when date_string is empty' do
      result = subject.parse_date_or_epoch('')
      expect(result).to eq(Time.zone.at(0))
    end

    it 'returns epoch for invalid date format' do
      result = subject.parse_date_or_epoch('invalid-date')
      expect(result).to eq(Time.zone.at(0))
    end

    it 'handles date with timezone offset' do
      result = subject.parse_date_or_epoch('2025-06-24T21:05:53+00:00')
      expect(result).to be_a(Time)
      expect(result.year).to eq(2025)
    end

    it 'handles date-only strings' do
      result = subject.parse_date_or_epoch('2025-06-24')
      expect(result).to be_a(Time)
      expect(result.year).to eq(2025)
      expect(result.month).to eq(6)
      expect(result.day).to eq(24)
    end
  end

  describe '#convert_to_facility_time' do
    it 'converts UTC time to facility local time' do
      # UTC time: 2023-11-06T18:32:00+00:00 (6:32 PM UTC)
      # Los Angeles is UTC-8 in November (PST), so local time should be 10:32 AM
      result = subject.convert_to_facility_time('2023-11-06T18:32:00+00:00', 'America/Los_Angeles')

      parsed = DateTime.parse(result)
      expect(parsed.hour).to eq(10)
      expect(parsed.min).to eq(32)
      expect(result).to include('-08:00')
    end

    it 'converts UTC time to Eastern time' do
      # UTC time: 2023-11-06T18:32:00+00:00 (6:32 PM UTC)
      # New York is UTC-5 in November (EST), so local time should be 1:32 PM
      result = subject.convert_to_facility_time('2023-11-06T18:32:00+00:00', 'America/New_York')

      parsed = DateTime.parse(result)
      expect(parsed.hour).to eq(13)
      expect(parsed.min).to eq(32)
      expect(result).to include('-05:00')
    end

    it 'converts UTC time with Z suffix' do
      # Common format from SCDF: 2023-11-06T18:32:00.000Z
      result = subject.convert_to_facility_time('2023-11-06T18:32:00.000Z', 'America/Los_Angeles')

      parsed = DateTime.parse(result)
      expect(parsed.hour).to eq(10)
      expect(parsed.min).to eq(32)
    end

    it 'correctly handles dates that already have non-UTC offsets' do
      # If the incoming date has -04:00 offset (e.g., from previous conversion or different source)
      # it should still convert correctly to the target timezone
      # 2023-11-06T14:32:00-04:00 = 2023-11-06T18:32:00 UTC = 2023-11-06T10:32:00 PST
      result = subject.convert_to_facility_time('2023-11-06T14:32:00-04:00', 'America/Los_Angeles')

      parsed = DateTime.parse(result)
      expect(parsed.hour).to eq(10)
      expect(parsed.min).to eq(32)
      expect(result).to include('-08:00')
    end

    it 'returns original date when timezone is blank' do
      original = '2023-11-06T18:32:00+00:00'
      expect(subject.convert_to_facility_time(original, nil)).to eq(original)
      expect(subject.convert_to_facility_time(original, '')).to eq(original)
    end

    it 'returns original date when date_string is blank' do
      expect(subject.convert_to_facility_time(nil, 'America/New_York')).to be_nil
      expect(subject.convert_to_facility_time('', 'America/New_York')).to eq('')
    end

    it 'returns original date and logs warning on parse error' do
      invalid_date = 'not-a-date'

      allow(Rails.logger).to receive(:warn).with(
        /Failed to convert time to facility timezone/,
        hash_including(service: 'unified_health_data')
      )

      result = subject.convert_to_facility_time(invalid_date, 'America/New_York')
      expect(result).to eq(invalid_date)
    end

    it 'returns original date and logs warning on invalid timezone' do
      valid_date = '2023-11-06T18:32:00+00:00'
      invalid_timezone = 'Invalid/Timezone'

      allow(Rails.logger).to receive(:warn).with(
        /Failed to convert time to facility timezone/,
        hash_including(service: 'unified_health_data')
      )

      result = subject.convert_to_facility_time(valid_date, invalid_timezone)
      expect(result).to eq(valid_date)
    end
  end

  describe '#normalize_date_to_noon_utc' do
    it 'normalizes an Eastern midnight date to noon UTC of the same day' do
      # VistA-style: midnight Eastern = 04:00 UTC
      result = subject.normalize_date_to_noon_utc('2025-09-25T04:00:00.000Z', 'America/New_York')
      expect(result).to eq('2025-09-25T12:00:00.000Z')
    end

    it 'normalizes an EDT-encoded VistA date to noon UTC' do
      result = subject.normalize_date_to_noon_utc('Thu, 25 Sep 2025 00:00:00 EDT', 'America/New_York')
      expect(result).to eq('2025-09-25T12:00:00.000Z')
    end

    it 'normalizes an EST-encoded VistA date to noon UTC' do
      result = subject.normalize_date_to_noon_utc('Mon, 15 Jan 2026 00:00:00 EST', 'America/New_York')
      expect(result).to eq('2026-01-15T12:00:00.000Z')
    end

    it 'normalizes an Oracle Health Pacific facility date correctly' do
      # OH: 23:59:59 PST Nov 16 = 07:59:59 UTC Nov 17
      result = subject.normalize_date_to_noon_utc('2026-11-17T07:59:59Z', 'America/Los_Angeles')
      expect(result).to eq('2026-11-16T12:00:00.000Z')
    end

    it 'normalizes an Oracle Health Central facility date correctly' do
      # OH: 23:59:59 CST Dec 31 = 05:59:59 UTC Jan 1
      result = subject.normalize_date_to_noon_utc('2027-01-01T05:59:59Z', 'America/Chicago')
      expect(result).to eq('2026-12-31T12:00:00.000Z')
    end

    it 'normalizes an Oracle Health Mountain facility date correctly' do
      # OH: 23:59:59 MST Nov 16 = 06:59:59 UTC Nov 17
      result = subject.normalize_date_to_noon_utc('2026-11-17T06:59:59Z', 'America/Denver')
      expect(result).to eq('2026-11-16T12:00:00.000Z')
    end

    it 'normalizes an Oracle Health Eastern facility date correctly' do
      # OH: 23:59:59 EST Nov 16 = 04:59:59 UTC Nov 17
      result = subject.normalize_date_to_noon_utc('2026-11-17T04:59:59Z', 'America/New_York')
      expect(result).to eq('2026-11-16T12:00:00.000Z')
    end

    it 'normalizes a Hawaii facility date correctly' do
      # OH: 23:59:59 HST Nov 16 = 09:59:59 UTC Nov 17
      result = subject.normalize_date_to_noon_utc('2026-11-17T09:59:59Z', 'Pacific/Honolulu')
      expect(result).to eq('2026-11-16T12:00:00.000Z')
    end

    it 'normalizes a Guam facility date correctly' do
      # OH: 23:59:59 ChST Nov 16 = 13:59:59 UTC Nov 16 (same UTC day)
      result = subject.normalize_date_to_noon_utc('2026-11-16T13:59:59Z', 'Pacific/Guam')
      expect(result).to eq('2026-11-16T12:00:00.000Z')
    end

    it 'normalizes a Manila facility date correctly' do
      # OH: 23:59:59 PST(+8) Nov 16 = 15:59:59 UTC Nov 16
      result = subject.normalize_date_to_noon_utc('2026-11-16T15:59:59Z', 'Asia/Manila')
      expect(result).to eq('2026-11-16T12:00:00.000Z')
    end

    it 'normalizes an American Samoa facility date correctly' do
      # OH: 23:59:59 SST Nov 16 = 10:59:59 UTC Nov 17
      result = subject.normalize_date_to_noon_utc('2026-11-17T10:59:59Z', 'Pacific/Pago_Pago')
      expect(result).to eq('2026-11-16T12:00:00.000Z')
    end

    it 'returns nil for blank date_string' do
      expect(subject.normalize_date_to_noon_utc(nil, 'America/New_York')).to be_nil
      expect(subject.normalize_date_to_noon_utc('', 'America/New_York')).to be_nil
    end

    it 'returns nil for blank timezone' do
      expect(subject.normalize_date_to_noon_utc('2025-09-25T04:00:00Z', nil)).to be_nil
      expect(subject.normalize_date_to_noon_utc('2025-09-25T04:00:00Z', '')).to be_nil
    end

    it 'returns nil for an invalid date string' do
      allow(Rails.logger).to receive(:warn)
      result = subject.normalize_date_to_noon_utc('not-a-date', 'America/New_York')
      expect(result).to be_nil
    end

    it 'handles date-only strings correctly' do
      result = subject.normalize_date_to_noon_utc('2025-09-25', 'America/New_York')
      expect(result).to eq('2025-09-25T12:00:00.000Z')
    end
  end

  describe '#normalize_date_for_sorting' do
    it 'returns 1900 epoch date for nil input' do
      result = subject.normalize_date_for_sorting(nil)
      expect(result).to eq('1900-01-01T00:00:00Z')
    end

    it 'normalizes year-only dates' do
      result = subject.normalize_date_for_sorting('2024')
      expect(result).to eq('2024-01-01T00:00:00Z')
    end

    it 'normalizes date-only strings without time' do
      result = subject.normalize_date_for_sorting('2024-11-08')
      expect(result).to eq('2024-11-08T00:00:00Z')
    end

    it 'passes through full datetime strings unchanged' do
      full_datetime = '2024-11-08T10:00:00Z'
      result = subject.normalize_date_for_sorting(full_datetime)
      expect(result).to eq(full_datetime)
    end

    it 'passes through datetime strings with timezone offsets unchanged' do
      datetime_with_offset = '2024-11-08T10:00:00-05:00'
      result = subject.normalize_date_for_sorting(datetime_with_offset)
      expect(result).to eq(datetime_with_offset)
    end

    it 'passes through datetime strings with milliseconds unchanged' do
      datetime_with_ms = '2024-11-08T10:00:00.000Z'
      result = subject.normalize_date_for_sorting(datetime_with_ms)
      expect(result).to eq(datetime_with_ms)
    end
  end
end
