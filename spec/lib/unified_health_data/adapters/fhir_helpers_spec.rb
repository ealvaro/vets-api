# frozen_string_literal: true

require 'rails_helper'
require 'unified_health_data/adapters/fhir_helpers'

describe UnifiedHealthData::Adapters::FhirHelpers do
  # Create a test class that includes the module
  subject { helper_class.new }

  let(:helper_class) do
    Class.new do
      include UnifiedHealthData::Adapters::FhirHelpers
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
      # parse_date_or_epoch returns epoch for invalid dates per commit cb4123e
      expect(result).to eq(Time.zone.at(0))
    end

    it 'returns epoch for invalid date format' do
      result = subject.parse_date_or_epoch('invalid-date')
      # parse_date_or_epoch returns epoch for invalid dates per commit cb4123e
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

  describe '#find_identifier_value' do
    let(:identifiers) do
      [
        { 'type' => { 'text' => 'Tracking Number' }, 'value' => 'TRK123' },
        { 'type' => { 'text' => 'Prescription Number' }, 'value' => 'RX456' },
        { 'type' => { 'text' => 'Carrier' }, 'value' => 'USPS' }
      ]
    end

    it 'finds identifier value by type text' do
      result = subject.find_identifier_value(identifiers, 'Tracking Number')
      expect(result).to eq('TRK123')
    end

    it 'returns nil when type text not found' do
      result = subject.find_identifier_value(identifiers, 'Unknown Type')
      expect(result).to be_nil
    end

    it 'returns nil for empty identifiers array' do
      result = subject.find_identifier_value([], 'Tracking Number')
      expect(result).to be_nil
    end

    it 'handles identifiers without value' do
      identifiers_without_value = [{ 'type' => { 'text' => 'Tracking Number' } }]
      result = subject.find_identifier_value(identifiers_without_value, 'Tracking Number')
      expect(result).to be_nil
    end
  end

  describe '#extract_codeable_concept_display' do
    context 'when codeable_concept is nil' do
      it 'returns nil' do
        expect(subject.extract_codeable_concept_display(nil)).to be_nil
      end
    end

    context 'with default prefer: :text' do
      it 'returns text when both text and coding display are present' do
        concept = { 'text' => 'Free text', 'coding' => [{ 'display' => 'Coded display' }] }
        expect(subject.extract_codeable_concept_display(concept)).to eq('Free text')
      end

      it 'falls back to coding display when text is absent' do
        concept = { 'coding' => [{ 'display' => 'Coded display' }] }
        expect(subject.extract_codeable_concept_display(concept)).to eq('Coded display')
      end

      it 'falls back to coding display when text is blank' do
        concept = { 'text' => '', 'coding' => [{ 'display' => 'Coded display' }] }
        expect(subject.extract_codeable_concept_display(concept)).to eq('Coded display')
      end

      it 'returns nil when both text and coding display are missing' do
        concept = { 'coding' => [{ 'code' => '12345' }] }
        expect(subject.extract_codeable_concept_display(concept)).to be_nil
      end

      it 'returns nil for empty hash' do
        expect(subject.extract_codeable_concept_display({})).to be_nil
      end

      it 'skips codings without display and returns one that has it' do
        concept = { 'coding' => [{ 'code' => 'A' }, { 'display' => 'Second' }] }
        expect(subject.extract_codeable_concept_display(concept)).to eq('Second')
      end
    end

    context 'with prefer: :coding' do
      it 'returns coding display when both text and coding display are present' do
        concept = { 'text' => 'Free text', 'coding' => [{ 'display' => 'Coded display' }] }
        expect(subject.extract_codeable_concept_display(concept, prefer: :coding)).to eq('Coded display')
      end

      it 'falls back to text when coding display is absent' do
        concept = { 'text' => 'Free text', 'coding' => [{ 'code' => '12345' }] }
        expect(subject.extract_codeable_concept_display(concept, prefer: :coding)).to eq('Free text')
      end

      it 'falls back to text when coding is nil' do
        concept = { 'text' => 'Free text' }
        expect(subject.extract_codeable_concept_display(concept, prefer: :coding)).to eq('Free text')
      end

      it 'returns nil when both are missing' do
        concept = { 'coding' => [{ 'code' => '12345' }] }
        expect(subject.extract_codeable_concept_display(concept, prefer: :coding)).to be_nil
      end
    end

    context 'when prefer is passed as a string' do
      it 'converts string to symbol and behaves like prefer: :coding' do
        concept = { 'text' => 'Free text', 'coding' => [{ 'display' => 'Coded display' }] }
        expect(subject.extract_codeable_concept_display(concept, prefer: 'coding')).to eq('Coded display')
      end

      it 'converts string to symbol and behaves like prefer: :text' do
        concept = { 'text' => 'Free text', 'coding' => [{ 'display' => 'Coded display' }] }
        expect(subject.extract_codeable_concept_display(concept, prefer: 'text')).to eq('Free text')
      end
    end
  end

  describe '#first_coding_display' do
    it 'returns the first coding display' do
      concept = { 'coding' => [{ 'display' => 'First' }, { 'display' => 'Second' }] }
      expect(subject.first_coding_display(concept)).to eq('First')
    end

    it 'skips codings without display' do
      concept = { 'coding' => [{ 'code' => 'A' }, { 'display' => 'Found' }] }
      expect(subject.first_coding_display(concept)).to eq('Found')
    end

    it 'returns nil when no coding has display' do
      concept = { 'coding' => [{ 'code' => 'A' }] }
      expect(subject.first_coding_display(concept)).to be_nil
    end

    it 'returns nil when coding is nil' do
      expect(subject.first_coding_display({})).to be_nil
    end

    it 'returns nil when coding is empty' do
      expect(subject.first_coding_display({ 'coding' => [] })).to be_nil
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
end
