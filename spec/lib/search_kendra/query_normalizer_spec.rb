# frozen_string_literal: true

require 'rails_helper'
require 'search_kendra/query_normalizer'

describe SearchKendra::QueryNormalizer do
  describe '.normalize' do
    it 'normalizes unknown query without replacement' do
      expect(described_class.normalize(' VA disability ')).to eq('va disability')
    end

    it 'replaces known queries' do
      expect(described_class.normalize('coe'))
        .to eq('certificate of eligibility')
    end

    it 'is case insensitive' do
      expect(described_class.normalize('CoE'))
        .to eq('certificate of eligibility')
    end

    it 'strips surrounding whitespace' do
      expect(described_class.normalize('  coe  '))
        .to eq('certificate of eligibility')
    end

    it 'handles nil query' do
      expect(described_class.normalize(nil))
        .to eq('')
    end
  end
end
