# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VAOS::V2::Unified::EpsSlot do
  describe '#initialize' do
    it 'sets provider_type to eps' do
      slot = described_class.new
      expect(slot.provider_type).to eq('eps')
    end
  end

  describe '.from_eps_slot' do
    let(:eps_slot_id) do
      '5vuTac8v-practitioner-1-role-2|e43a19a8-b0cb-4dcf-befa-8cc511c3999b|' \
        '2025-01-02T11:00:00Z|30m0s|1736636444704|ov'
    end

    let(:eps_slot) do
      {
        id: eps_slot_id,
        provider_service_id: '9mN718pH',
        start: '2025-01-02T11:00:00Z',
        end: nil
      }
    end

    it 'maps EPS slot fields to EpsSlot' do
      slot = described_class.from_eps_slot(eps_slot)

      expect(slot.id).to eq(eps_slot_id)
      expect(slot.start).to eq('2025-01-02T11:00:00Z')
      expect(slot.end).to eq('2025-01-02T11:30:00Z')
      expect(slot.provider_id).to eq('9mN718pH')
      expect(slot.provider_type).to eq('eps')
      expect(slot.provider_service_id).to eq('9mN718pH')
    end

    it 'works with OpenStruct input' do
      slot = described_class.from_eps_slot(OpenStruct.new(eps_slot))

      expect(slot.id).to include('5vuTac8v-practitioner')
      expect(slot.provider_type).to eq('eps')
    end

    it 'handles missing provider_service_id gracefully' do
      eps_slot.delete(:provider_service_id)
      slot = described_class.from_eps_slot(eps_slot)

      expect(slot.provider_id).to be_nil
      expect(slot.provider_service_id).to be_nil
    end

    it 'returns nil end when slot ID has no parseable duration segment' do
      eps_slot[:id] = 'no-pipe-segments'
      eps_slot[:end] = nil
      slot = described_class.from_eps_slot(eps_slot)

      expect(slot.end).to be_nil
    end

    it 'preserves an explicit end time when present' do
      eps_slot[:end] = '2025-01-02T11:45:00Z'
      slot = described_class.from_eps_slot(eps_slot)

      expect(slot.end).to eq('2025-01-02T11:45:00Z')
    end
  end
end
