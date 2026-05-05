# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VAOS::V2::Unified::ParentStationFilter do
  describe '.parent_id_for' do
    {
      '983' => '983',
      '983GC' => '983',
      '442' => '442',
      '442QA' => '442',
      '442GA' => '442',
      '123AB' => '123',
      '5' => '5',
      '0001' => '0001',
      '983GC-extra-junk' => '983',
      '' => nil,
      nil => nil,
      'AB123' => nil,
      'noop' => nil
    }.each do |input, expected|
      it "extracts #{expected.inspect} from #{input.inspect}" do
        expect(described_class.parent_id_for(input)).to eq(expected)
      end
    end

    it 'tolerates Integer input' do
      expect(described_class.parent_id_for(983)).to eq('983')
    end
  end

  describe '.parse' do
    {
      nil => [],
      '' => [],
      '   ' => [],
      '983' => ['983'],
      '983,442' => %w[983 442],
      '983, 442' => %w[983 442],
      ' 983 , 442 ' => %w[983 442],
      '983,,442' => %w[983 442],
      '983, , ,442' => %w[983 442],
      '983,442,983' => %w[983 442]
    }.each do |raw, expected|
      it "parses #{raw.inspect} -> #{expected.inspect}" do
        expect(described_class.parse(raw)).to eq(expected)
      end
    end
  end

  describe 'allowlist behavior driven by Settings' do
    let(:configured_value) { nil }

    before do
      allow(Settings.vaos.unified_scheduling)
        .to receive(:allowed_parent_stations).and_return(configured_value)
    end

    context 'when the setting is unset / blank' do
      [nil, '', '   '].each do |blank_value|
        context "with #{blank_value.inspect}" do
          let(:configured_value) { blank_value }

          it '#enabled? is false (filter disabled)' do
            expect(described_class.enabled?).to be(false)
          end

          it '#allowed? returns true for any input (no filter applied)' do
            expect(described_class.allowed?('983')).to be(true)
            expect(described_class.allowed?('999XYZ')).to be(true)
            expect(described_class.allowed?(nil)).to be(true)
          end
        end
      end
    end

    context 'when the setting has a comma-delimited list' do
      let(:configured_value) { '983, 442' }

      it '#enabled? is true' do
        expect(described_class.enabled?).to be(true)
      end

      it '#allowed_parents strips whitespace and returns the parsed list' do
        expect(described_class.allowed_parents).to eq(%w[983 442])
      end

      it 'allows exact-match parent station IDs' do
        expect(described_class.allowed?('983')).to be(true)
        expect(described_class.allowed?('442')).to be(true)
      end

      it 'allows satellite/CBOC station IDs that roll up to an allowed parent' do
        expect(described_class.allowed?('983GC')).to be(true)
        expect(described_class.allowed?('442GA')).to be(true)
        expect(described_class.allowed?('442QA')).to be(true)
      end

      it 'rejects station IDs whose parent is not in the list' do
        expect(described_class.allowed?('552')).to be(false)
        expect(described_class.allowed?('552GA')).to be(false)
      end

      it 'rejects inputs from which no parent can be derived' do
        expect(described_class.allowed?(nil)).to be(false)
        expect(described_class.allowed?('')).to be(false)
        expect(described_class.allowed?('AB123')).to be(false)
      end
    end

    context 'with extra whitespace and a single entry' do
      let(:configured_value) { '   983   ' }

      it 'still treats the filter as enabled and allows only that station' do
        expect(described_class.enabled?).to be(true)
        expect(described_class.allowed?('983')).to be(true)
        expect(described_class.allowed?('983GC')).to be(true)
        expect(described_class.allowed?('442')).to be(false)
      end
    end
  end
end
