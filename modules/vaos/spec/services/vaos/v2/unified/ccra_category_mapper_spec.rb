# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VAOS::V2::Unified::CcraCategoryMapper do
  before do
    allow(Rails.logger).to receive(:warn)
    allow(StatsD).to receive(:increment)
  end

  # A CCRA category that is intentionally NOT in CCRA_TO_TARGETS, used to
  # exercise the "truly unmapped" fallback path. Pick something we'd be
  # surprised to see CCRA actually emit (so we don't accidentally collide with
  # a future starter-table addition).
  let(:unmapped_ccra_category) { 'TOTALLY UNKNOWN SPECIALTY' }

  describe '.lookup -> :vaos_service_type' do
    it "maps 'PRIMARY CARE' to 'primaryCare'" do
      expect(described_class.lookup('PRIMARY CARE')[:vaos_service_type]).to eq('primaryCare')
    end

    it 'is case-insensitive for primary care (handles CCRA casing variations)' do
      expect(described_class.lookup('primary care')[:vaos_service_type]).to eq('primaryCare')
      expect(described_class.lookup('Primary Care')[:vaos_service_type]).to eq('primaryCare')
    end

    it 'trims surrounding whitespace before lookup' do
      expect(described_class.lookup('  PRIMARY CARE  ')[:vaos_service_type]).to eq('primaryCare')
    end

    it "defaults to 'primaryCare' for an unmapped category (pilot fallback)" do
      expect(described_class.lookup(unmapped_ccra_category)[:vaos_service_type]).to eq('primaryCare')
    end

    it "defaults to 'primaryCare' for nil input (pilot fallback)" do
      expect(described_class.lookup(nil)[:vaos_service_type]).to eq('primaryCare')
    end

    it "defaults to 'primaryCare' for blank input (pilot fallback)" do
      expect(described_class.lookup('')[:vaos_service_type]).to eq('primaryCare')
      expect(described_class.lookup('   ')[:vaos_service_type]).to eq('primaryCare')
    end

    it "returns the entry's mapped VAOS service type when there's no user (backend-trust path)" do
      expect(described_class.lookup('AUDIOLOGY')[:vaos_service_type]).to eq('audiology')
      expect(described_class.lookup('OPTOMETRY')[:vaos_service_type]).to eq('optometry')
    end
  end

  describe '.lookup -> :eps_nucc_specialty_ids' do
    it "returns the primary-care NUCC IDs for 'PRIMARY CARE'" do
      expect(described_class.lookup('PRIMARY CARE')[:eps_nucc_specialty_ids])
        .to contain_exactly('207Q00000X', '207R00000X', '208D00000X')
    end

    it "returns the entry's NUCC IDs for a mapped non-PC category (no user)" do
      expect(described_class.lookup('CHIROPRACTIC')[:eps_nucc_specialty_ids])
        .to contain_exactly('111N00000X')
    end

    it 'falls back to PC NUCC IDs for an unmapped category (pilot fallback)' do
      expect(described_class.lookup(unmapped_ccra_category)[:eps_nucc_specialty_ids])
        .to contain_exactly('207Q00000X', '207R00000X', '208D00000X')
    end

    it 'falls back to PC NUCC IDs for nil input (pilot fallback)' do
      expect(described_class.lookup(nil)[:eps_nucc_specialty_ids])
        .to contain_exactly('207Q00000X', '207R00000X', '208D00000X')
    end

    it 'falls back to PC NUCC IDs for blank input (pilot fallback)' do
      expect(described_class.lookup('')[:eps_nucc_specialty_ids])
        .to contain_exactly('207Q00000X', '207R00000X', '208D00000X')
    end
  end

  describe '.lookup -> :eps_name_match_patterns' do
    it "returns all primary-care patterns for 'PRIMARY CARE'" do
      patterns = described_class.lookup('PRIMARY CARE')[:eps_name_match_patterns]

      expect(patterns).to all(be_a(Regexp))
      expect(patterns.size).to eq(4)
    end

    {
      'Primary Care' => /primary\s+care/i,
      'PRIMARY CARE PHYSICIAN' => /primary\s+care/i,
      'primary  care' => /primary\s+care/i, # double-space tolerated by \s+
      'Family Medicine' => /family\s+medicine/i,
      'FAMILY MEDICINE' => /family\s+medicine/i,
      'Internal Medicine' => /internal\s+medicine/i,
      'General Practice' => /general\s+practice/i
    }.each do |sample, expected_pattern|
      it "matches '#{sample}' against at least one PRIMARY CARE pattern" do
        patterns = described_class.lookup('PRIMARY CARE')[:eps_name_match_patterns]
        expect(patterns.any? { |p| sample.match?(p) }).to be(true),
                                                          "expected one of #{patterns} to match '#{sample}'"
        expect(sample).to match(expected_pattern)
      end
    end

    it 'does not match unrelated specialties against PRIMARY CARE patterns' do
      patterns = described_class.lookup('PRIMARY CARE')[:eps_name_match_patterns]

      %w[Urology Cardiology Dermatology Optometrist].each do |unrelated|
        expect(patterns.any? { |p| unrelated.match?(p) }).to be(false)
      end
    end

    it 'is case-insensitive at the lookup level (category input)' do
      expect(described_class.lookup('primary care')[:eps_name_match_patterns].size).to eq(4)
    end

    it 'falls back to PC patterns for an unmapped category (pilot fallback)' do
      patterns = described_class.lookup(unmapped_ccra_category)[:eps_name_match_patterns]
      expect(patterns).to all(be_a(Regexp))
      expect(patterns.size).to eq(4)
    end

    it 'falls back to PC patterns for nil input (pilot fallback)' do
      expect(described_class.lookup(nil)[:eps_name_match_patterns].size).to eq(4)
    end

    it 'falls back to PC patterns for blank input (pilot fallback)' do
      expect(described_class.lookup('')[:eps_name_match_patterns].size).to eq(4)
    end
  end

  describe 'unmapped category logging' do
    it 'logs a warning and increments StatsD when category is unknown' do
      described_class.lookup(unmapped_ccra_category)

      expect(Rails.logger).to have_received(:warn).with(
        'CcraCategoryMapper: unmapped category_of_care, defaulting to primaryCare',
        category_of_care: 'TOTALLY_UNKNOWN_SPECIALTY'
      )
      expect(StatsD).to have_received(:increment).with(
        'api.vaos.ccra_category_mapper.unmapped',
        tags: ['category_of_care:TOTALLY_UNKNOWN_SPECIALTY']
      )
    end

    it 'sanitizes whitespace in the StatsD tag value (no raw spaces emitted)' do
      described_class.lookup('SOME UNKNOWN SPECIALTY')

      expect(StatsD).to have_received(:increment).with(
        'api.vaos.ccra_category_mapper.unmapped',
        tags: ['category_of_care:SOME_UNKNOWN_SPECIALTY']
      )
    end

    it 'still logs (tagged no_value) for blank input so silent PC defaulting is visible' do
      described_class.lookup(nil)

      expect(Rails.logger).to have_received(:warn).with(
        'CcraCategoryMapper: unmapped category_of_care, defaulting to primaryCare',
        category_of_care: 'no_value'
      )
      expect(StatsD).to have_received(:increment).with(
        'api.vaos.ccra_category_mapper.unmapped',
        tags: ['category_of_care:no_value']
      )
    end

    it 'logs once per call for empty-string and whitespace-only input' do
      described_class.lookup('')
      described_class.lookup('   ')

      expect(Rails.logger).to have_received(:warn).twice
      expect(StatsD).to have_received(:increment).twice.with(
        'api.vaos.ccra_category_mapper.unmapped',
        tags: ['category_of_care:no_value']
      )
    end

    it 'does not log for mapped categories (PRIMARY CARE or any known non-PC entry)' do
      described_class.lookup('PRIMARY CARE')
      described_class.lookup('AUDIOLOGY')
      described_class.lookup('CHIROPRACTIC')

      expect(Rails.logger).not_to have_received(:warn)
      expect(StatsD).not_to have_received(:increment)
    end
  end

  describe '.lookup' do
    it 'returns all mapped outputs in a single call (preferred for callers that need all three)' do
      result = described_class.lookup('PRIMARY CARE')

      expect(result[:vaos_service_type]).to eq('primaryCare')
      expect(result[:eps_nucc_specialty_ids]).to contain_exactly('207Q00000X', '207R00000X', '208D00000X')
      expect(result[:eps_name_match_patterns]).to all(be_a(Regexp))
      expect(result[:eps_name_match_patterns].size).to eq(4)
    end

    it 'logs exactly once per call for unmapped categories' do
      described_class.lookup(unmapped_ccra_category)

      expect(Rails.logger).to have_received(:warn).once
      expect(StatsD).to have_received(:increment).once
    end

    it 'returns the PRIMARY_CARE_DEFAULTS bundle for unmapped categories' do
      result = described_class.lookup(unmapped_ccra_category)

      expect(result).to eq(described_class::PRIMARY_CARE_DEFAULTS)
      expect(result[:vaos_service_type]).to eq('primaryCare')
      expect(result[:eps_nucc_specialty_ids]).to eq(%w[207Q00000X 207R00000X 208D00000X])
      expect(result[:eps_name_match_patterns]).to all(be_a(Regexp))
    end

    it 'merges per-section so future entries can override only the fields they define' do
      partial_entry = { vaos_service_type: 'cardiology' }.freeze
      stub_const(
        "#{described_class}::CCRA_TO_TARGETS",
        described_class::CCRA_TO_TARGETS.merge('CARDIOLOGY' => partial_entry).freeze
      )

      result = described_class.lookup('CARDIOLOGY')

      expect(result[:vaos_service_type]).to eq('cardiology')
      expect(result[:eps_nucc_specialty_ids])
        .to eq(described_class::PRIMARY_CARE_DEFAULTS[:eps_nucc_specialty_ids])
      expect(result[:eps_name_match_patterns])
        .to eq(described_class::PRIMARY_CARE_DEFAULTS[:eps_name_match_patterns])

      expect(Rails.logger).not_to have_received(:warn)
    end

    it 'inherits PC vaos_service_type for entries that intentionally leave it nil (e.g. CHIROPRACTIC)' do
      result = described_class.lookup('CHIROPRACTIC')

      expect(result[:vaos_service_type]).to eq('primaryCare')
      expect(result[:eps_nucc_specialty_ids]).to eq(%w[111N00000X])
      expect(Rails.logger).not_to have_received(:warn)
    end
  end

  describe 'pilot kill-switch (va_online_scheduling_unified_non_primary_care)' do
    let(:user) { build(:user, :vaos) }

    before do
      allow(Flipper).to receive(:enabled?).and_call_original
    end

    context 'when the flag is DISABLED for the user (default pilot mode)' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(described_class::PILOT_PC_ONLY_FLAG, user).and_return(false)
      end

      it 'overrides a known non-PC entry (AUDIOLOGY) to PRIMARY_CARE_DEFAULTS' do
        result = described_class.lookup('AUDIOLOGY', user:)

        expect(result).to eq(described_class::PRIMARY_CARE_DEFAULTS)
      end

      it 'overrides a known EPS-only entry (CHIROPRACTIC) to PRIMARY_CARE_DEFAULTS' do
        result = described_class.lookup('CHIROPRACTIC', user:)

        expect(result).to eq(described_class::PRIMARY_CARE_DEFAULTS)
      end

      it 'leaves PRIMARY CARE alone (no override log)' do
        described_class.lookup('PRIMARY CARE', user:)

        expect(Rails.logger).not_to have_received(:warn).with(
          /pilot is PC-only/, anything
        )
      end

      it 'logs a pc_override warning + StatsD counter when overriding a non-PC entry' do
        described_class.lookup('AUDIOLOGY', user:)

        expect(Rails.logger).to have_received(:warn).with(
          'CcraCategoryMapper: pilot is PC-only, overriding mapped category to primaryCare',
          hash_including(
            category_of_care: 'AUDIOLOGY',
            suppressed_vaos_service_type: 'audiology',
            suppressed_eps_nucc_specialty_ids: %w[231H00000X]
          )
        )
        expect(StatsD).to have_received(:increment).with(
          'api.vaos.ccra_category_mapper.pc_override',
          tags: ['category_of_care:AUDIOLOGY']
        )
      end

      # Regression guard: for EPS-only entries (e.g. CARDIOLOGY, CHIROPRACTIC)
      # the +vaos_service_type+ inherits the PC default of 'primaryCare', so
      # the suppressed VAOS type alone is misleading. The NUCC ids are the
      # actually-suppressed signal and must be in the log payload.
      it 'logs the suppressed NUCC ids for EPS-only entries whose VAOS type inherits primaryCare' do
        described_class.lookup('CHIROPRACTIC', user:)

        expect(Rails.logger).to have_received(:warn).with(
          'CcraCategoryMapper: pilot is PC-only, overriding mapped category to primaryCare',
          hash_including(
            category_of_care: 'CHIROPRACTIC',
            suppressed_vaos_service_type: 'primaryCare',
            suppressed_eps_nucc_specialty_ids: %w[111N00000X]
          )
        )
      end

      it 'still logs unmapped (and overrides to PC) for a truly unknown category' do
        described_class.lookup(unmapped_ccra_category, user:)

        expect(Rails.logger).to have_received(:warn).with(
          'CcraCategoryMapper: unmapped category_of_care, defaulting to primaryCare',
          hash_including(category_of_care: 'TOTALLY_UNKNOWN_SPECIALTY')
        )
        # Unmapped already collapses to PC defaults, so no separate pc_override fires.
        expect(Rails.logger).not_to have_received(:warn).with(
          /pilot is PC-only/, anything
        )
      end
    end

    context 'when the flag is ENABLED for the user (pilot expanded)' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(described_class::PILOT_PC_ONLY_FLAG, user).and_return(true)
      end

      it "returns the entry's mapped values for AUDIOLOGY (no PC override)" do
        result = described_class.lookup('AUDIOLOGY', user:)

        expect(result[:vaos_service_type]).to eq('audiology')
        expect(result[:eps_nucc_specialty_ids]).to eq(%w[231H00000X])
      end

      it 'returns CHIROPRACTIC NUCC ids while VAOS service inherits primaryCare' do
        result = described_class.lookup('CHIROPRACTIC', user:)

        expect(result[:vaos_service_type]).to eq('primaryCare')
        expect(result[:eps_nucc_specialty_ids]).to eq(%w[111N00000X])
      end

      it 'does not log a pc_override warning' do
        described_class.lookup('AUDIOLOGY', user:)

        expect(Rails.logger).not_to have_received(:warn).with(
          /pilot is PC-only/, anything
        )
      end

      it 'still falls back to PC for truly unmapped categories' do
        result = described_class.lookup(unmapped_ccra_category, user:)

        expect(result).to eq(described_class::PRIMARY_CARE_DEFAULTS)
      end
    end

    context 'with no user (backend-only paths that omit the +user:+ kwarg)' do
      it "trusts the table -- returns AUDIOLOGY's mapped VAOS type" do
        expect(described_class.lookup('AUDIOLOGY')[:vaos_service_type]).to eq('audiology')
      end

      it "trusts the table -- returns CHIROPRACTIC's NUCC ids" do
        expect(described_class.lookup('CHIROPRACTIC')[:eps_nucc_specialty_ids]).to eq(%w[111N00000X])
      end
    end

    context 'when the Flipper check itself raises (defensive)' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(described_class::PILOT_PC_ONLY_FLAG, user).and_raise(StandardError, 'flipper down')
      end

      it 'fails closed to PC routing' do
        result = described_class.lookup('AUDIOLOGY', user:)

        expect(result).to eq(described_class::PRIMARY_CARE_DEFAULTS)
      end

      it 'logs the failure for visibility' do
        described_class.lookup('AUDIOLOGY', user:)

        expect(Rails.logger).to have_received(:warn).with(
          'api.vaos.ccra_category_mapper.pilot_flag_check_failed',
          hash_including(error_class: 'StandardError', error_message: 'flipper down')
        )
      end
    end
  end

  describe 'CCRA_TO_TARGETS constant' do
    it 'is frozen' do
      expect(described_class::CCRA_TO_TARGETS).to be_frozen
    end

    it 'guarantees PRIMARY CARE is mapped' do
      expect(described_class::CCRA_TO_TARGETS).to have_key('PRIMARY CARE')
    end

    it 'maps VAOS service types that appear in SCHEDULABLE_SERVICE_TYPES' do
      schedulable = VAOS::V2::AppointmentsService::SCHEDULABLE_SERVICE_TYPES
      described_class::CCRA_TO_TARGETS.each_value do |entry|
        next if entry[:vaos_service_type].nil?

        expect(schedulable).to include(entry[:vaos_service_type]),
                               "VAOS type '#{entry[:vaos_service_type]}' not in SCHEDULABLE_SERVICE_TYPES"
      end
    end

    it 'all entries are frozen (immutable at runtime)' do
      described_class::CCRA_TO_TARGETS.each_value do |entry|
        expect(entry).to be_frozen
      end
    end

    it 'every entry that defines NUCC ids defines a non-empty array' do
      described_class::CCRA_TO_TARGETS.each do |key, entry|
        next unless entry.key?(:eps_nucc_specialty_ids)

        ids = entry[:eps_nucc_specialty_ids]
        expect(ids).to be_a(Array), "#{key} NUCC ids must be an Array"
        expect(ids).not_to be_empty, "#{key} NUCC ids must not be empty"
        expect(ids).to all(match(/\A\d{3}[A-Z\d]{7}\z/i)),
                       "#{key} NUCC ids must look like a NUCC taxonomy code"
      end
    end
  end

  describe 'PRIMARY_CARE_DEFAULTS constant' do
    it 'is frozen' do
      expect(described_class::PRIMARY_CARE_DEFAULTS).to be_frozen
    end

    it 'provides all three downstream targets' do
      expect(described_class::PRIMARY_CARE_DEFAULTS)
        .to include(:vaos_service_type, :eps_nucc_specialty_ids, :eps_name_match_patterns)
    end

    it 'is the same value as the PRIMARY CARE entry (single source of truth)' do
      expect(described_class::CCRA_TO_TARGETS['PRIMARY CARE'])
        .to eq(described_class::PRIMARY_CARE_DEFAULTS)
    end
  end
end
