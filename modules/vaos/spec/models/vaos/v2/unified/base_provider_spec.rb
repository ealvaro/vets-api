# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VAOS::V2::Unified::BaseProvider do
  describe '#initialize' do
    it 'accepts attributes via hash' do
      provider = described_class.new(
        id: '123',
        name: 'Test Provider',
        latitude: 40.7128,
        longitude: -74.006,
        provider_type: 'va'
      )

      expect(provider.id).to eq('123')
      expect(provider.name).to eq('Test Provider')
      expect(provider.latitude).to eq(40.7128)
      expect(provider.longitude).to eq(-74.006)
      expect(provider.provider_type).to eq('va')
    end
  end

  describe '#online_scheduling?' do
    it 'defaults to true (VA providers reach the list only after a direct-eligible check)' do
      provider = described_class.new

      expect(provider.online_scheduling?).to be true
    end
  end

  describe '#formatted_address' do
    it 'joins address parts with commas' do
      provider = described_class.new(
        address: { street1: '123 Main St', city: 'Springfield', state: 'IL', zip: '62701' }
      )

      expect(provider.formatted_address).to eq('123 Main St, Springfield, IL, 62701')
    end

    it 'returns nil when address is blank' do
      provider = described_class.new
      expect(provider.formatted_address).to be_nil
    end

    it 'skips nil address parts' do
      provider = described_class.new(
        address: { street1: '123 Main St', city: 'Springfield', state: nil, zip: '62701' }
      )

      expect(provider.formatted_address).to eq('123 Main St, Springfield, 62701')
    end
  end
end
