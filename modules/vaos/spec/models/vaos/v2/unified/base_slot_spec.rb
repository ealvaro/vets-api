# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VAOS::V2::Unified::BaseSlot do
  describe '#initialize' do
    it 'accepts attributes via hash' do
      slot = described_class.new(
        id: 'slot-123',
        start: '2025-01-02T11:00:00Z',
        end: '2025-01-02T11:30:00Z',
        provider_id: 'provider-456',
        provider_type: 'va'
      )

      expect(slot.id).to eq('slot-123')
      expect(slot.start).to eq('2025-01-02T11:00:00Z')
      expect(slot.end).to eq('2025-01-02T11:30:00Z')
      expect(slot.provider_id).to eq('provider-456')
      expect(slot.provider_type).to eq('va')
    end

    it 'defaults all attributes to nil' do
      slot = described_class.new

      expect(slot.id).to be_nil
      expect(slot.start).to be_nil
      expect(slot.end).to be_nil
      expect(slot.provider_id).to be_nil
      expect(slot.provider_type).to be_nil
    end

    it 'ignores unknown attributes' do
      slot = described_class.new(id: 'slot-123', unknown_field: 'ignored')

      expect(slot.id).to eq('slot-123')
      expect(slot).not_to respond_to(:unknown_field)
    end
  end
end
