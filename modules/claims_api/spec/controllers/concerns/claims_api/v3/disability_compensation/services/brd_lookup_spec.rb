# frozen_string_literal: true

require 'rails_helper'
require 'brd/brd'

RSpec.describe ClaimsApi::V3::DisabilityCompensation::Services::BrdLookup, type: :model do
  let(:brd) { instance_double(ClaimsApi::BRD) }

  before do
    allow(ClaimsApi::BRD).to receive(:new).and_return(brd)
  end

  describe '#active_classification_ids' do
    it 'returns integer ids pulled from BRD.disabilities' do
      allow(brd).to receive(:disabilities).and_return(
        [
          { id: 9014, endDateTime: nil },
          { id: 9020, endDateTime: nil }
        ]
      )

      expect(described_class.new.active_classification_ids).to eq([9014, 9020])
    end
  end

  describe '#classification_end_date_for' do
    it 'returns the parsed Date of the endDateTime for the given id' do
      allow(brd).to receive(:disabilities).and_return(
        [
          { id: 9014, endDateTime: '2020-01-15T00:00:00Z' },
          { id: 9020, endDateTime: nil }
        ]
      )

      expect(described_class.new.classification_end_date_for(9014)).to eq(Date.new(2020, 1, 15))
    end

    it 'returns nil when the entry has a nil endDateTime' do
      allow(brd).to receive(:disabilities).and_return(
        [
          { id: 9020, endDateTime: nil }
        ]
      )

      expect(described_class.new.classification_end_date_for(9020)).to be_nil
    end

    it 'returns nil when no entry matches the given id' do
      allow(brd).to receive(:disabilities).and_return(
        [
          { id: 9014, endDateTime: '2020-01-15T00:00:00Z' }
        ]
      )

      expect(described_class.new.classification_end_date_for(9999)).to be_nil
    end
  end

  describe 'memoization' do
    it 'fetches disabilities from BRD only once across multiple method calls' do
      allow(brd).to receive(:disabilities).and_return(
        [
          { id: 9014, endDateTime: nil }
        ]
      )

      lookup = described_class.new
      lookup.active_classification_ids
      lookup.classification_end_date_for(9014)
      lookup.active_classification_ids

      expect(brd).to have_received(:disabilities).once
    end
  end
end
