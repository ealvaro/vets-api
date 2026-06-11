# frozen_string_literal: true

require 'rails_helper'
require 'claims_api/contention_parser'

RSpec.describe ClaimsApi::ContentionParser do
  describe '.parse' do
    it 'returns empty array for blank input' do
      expect(described_class.parse('')).to eq([])
    end

    context 'when disability names contain commas' do
      it 'extracts multiple disabilities when names have embedded commas' do
        raw = 'Ear infection (bad), right side (New), Tooth pain (Secondary)'

        expect(described_class.parse(raw)).to eq([
                                                   'Ear infection (bad), right side (New)',
                                                   'Tooth pain (Secondary)'
                                                 ])
      end

      it 'extracts a single disability with embedded commas in the name' do
        raw = 'chronic otitis externa (swimmers ear), right (New)'

        expect(described_class.parse(raw)).to eq(['chronic otitis externa (swimmers ear), right (New)'])
      end
    end

    context 'when input contains similar string values as the valid action types' do
      it 'ignores uppercase (NEW) and only matches valid lowercase action types' do
        raw = 'Ear infection (NEW), right (New)'

        expect(described_class.parse(raw)).to eq(['Ear infection (NEW), right (New)'])
      end
    end

    it 'does not match longer parenthetical values like (New Year) or (None so far)' do
      raw = 'chronic issue (New Year), follow up (None so far), right (New)'

      expect(described_class.parse(raw)).to eq([raw])
    end

    it 'does not match None or Secondary as plain strings' do
      secondary_as_string = 'Secondary Arm Pain, right (New)'
      none_as_string = 'None on the left, pain on the right side (Increase)'

      expect(described_class.parse(secondary_as_string)).to eq([secondary_as_string])
      expect(described_class.parse(none_as_string)).to eq([none_as_string])
    end

    it 'parses multiple tagged entries without trailing comma' do
      raw = 'Headache (New), Back pain (None)'

      expect(described_class.parse(raw)).to eq(['Headache (New)', 'Back pain (None)'])
    end
  end
end
