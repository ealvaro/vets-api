# frozen_string_literal: true

require 'rails_helper'
require 'claims_api/evss_bgs_mapper'

describe ClaimsApi::EvssBgsMapper do
  describe '#contentions' do
    context 'when contentions string contains disability names with embedded commas' do
      it 'correctly parses multiple disabilities with embedded commas in names' do
        bgs_data = {
          'benefit_claim_id' => '12345',
          'contentions' => 'Ear infection (bad), right side (New), Tooth pain (Secondary)'
        }
        mapper = described_class.new(bgs_data)

        contentions = mapper.send(:contentions)

        expect(contentions).to eq(['Ear infection (bad), right side (New)', 'Tooth pain (Secondary)'])
      end

      it 'preserves commas within a single disability name' do
        bgs_data = {
          'benefit_claim_id' => '12345',
          'contentions' => 'chronic otitis externa (swimmers ear), right (New)'
        }
        mapper = described_class.new(bgs_data)

        contentions = mapper.send(:contentions)

        expect(contentions).to eq(['chronic otitis externa (swimmers ear), right (New)'])
      end
    end

    context 'when contentions are well-formed with only valid action types' do
      it 'parses multiple entries with valid action types' do
        bgs_data = {
          'benefit_claim_id' => '12345',
          'contentions' => 'Back pain (Increase), Headache (New), Anxiety (Secondary)'
        }
        mapper = described_class.new(bgs_data)

        contentions = mapper.send(:contentions)

        expect(contentions).to eq(['Back pain (Increase)', 'Headache (New)', 'Anxiety (Secondary)'])
      end
    end

    context 'when contentions contain edge cases' do
      it 'ignores uppercase (NEW) and only matches valid lowercase action types' do
        bgs_data = {
          'benefit_claim_id' => '12345',
          'contentions' => 'Ear infection (NEW), right (New)'
        }
        mapper = described_class.new(bgs_data)

        contentions = mapper.send(:contentions)

        expect(contentions).to eq(['Ear infection (NEW), right (New)'])
      end

      it 'does not split on longer parentheticals like (New Year)' do
        bgs_data = {
          'benefit_claim_id' => '12345',
          'contentions' => 'chronic issue (New Year), follow up (None so far), right (New)'
        }
        mapper = described_class.new(bgs_data)

        contentions = mapper.send(:contentions)

        expect(contentions).to eq(['chronic issue (New Year), follow up (None so far), right (New)'])
      end
    end

    context 'when contentions are blank or nil' do
      it 'returns empty array when contentions is nil' do
        bgs_data = { 'benefit_claim_id' => '12345', 'contentions' => nil }
        mapper = described_class.new(bgs_data)

        contentions = mapper.send(:contentions)

        expect(contentions).to eq([])
      end

      it 'returns empty array when contentions is blank string' do
        bgs_data = { 'benefit_claim_id' => '12345', 'contentions' => '' }
        mapper = described_class.new(bgs_data)

        contentions = mapper.send(:contentions)

        expect(contentions).to eq([])
      end

      it 'returns empty array when contentions key is missing' do
        bgs_data = { 'benefit_claim_id' => '12345' }
        mapper = described_class.new(bgs_data)

        contentions = mapper.send(:contentions)

        expect(contentions).to eq([])
      end
    end
  end
end
