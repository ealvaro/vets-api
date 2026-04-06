# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VAOS::V2::Unified::VASlot do
  describe '#initialize' do
    it 'sets provider_type to va' do
      slot = described_class.new
      expect(slot.provider_type).to eq('va')
    end
  end

  describe '.from_vaos_slot' do
    let(:vaos_slot) do
      {
        id: '3230323530313032323A323033303030303030303030',
        start: '2025-01-02T20:30:00Z',
        end: '2025-01-02T21:00:00Z',
        location: { vha_facility_id: '757GC', name: 'Marion VA Clinic' },
        clinic: { clinic_ien: '455', name: 'MARION CBOC PODIATRY' },
        practitioner: { name: 'Doe, John D, MD' }
      }
    end

    it 'maps VAOS slot fields to VaSlot' do
      slot = described_class.from_vaos_slot(vaos_slot)

      expect(slot.id).to eq('3230323530313032323A323033303030303030303030')
      expect(slot.start).to eq('2025-01-02T20:30:00Z')
      expect(slot.end).to eq('2025-01-02T21:00:00Z')
      expect(slot.provider_id).to eq('455')
      expect(slot.provider_type).to eq('va')
      expect(slot.location_id).to eq('757GC')
      expect(slot.clinic_ien).to eq('455')
    end

    it 'allows location_id override via keyword argument' do
      slot = described_class.from_vaos_slot(vaos_slot, location_id: '983')

      expect(slot.provider_id).to eq('455')
      expect(slot.location_id).to eq('983')
    end

    it 'works with OpenStruct input' do
      slot = described_class.from_vaos_slot(OpenStruct.new(vaos_slot))

      expect(slot.id).to eq('3230323530313032323A323033303030303030303030')
      expect(slot.provider_type).to eq('va')
    end

    it 'handles missing location gracefully' do
      vaos_slot.delete(:location)
      slot = described_class.from_vaos_slot(vaos_slot)

      expect(slot.provider_id).to eq('455')
      expect(slot.location_id).to be_nil
    end

    it 'handles missing clinic gracefully' do
      vaos_slot.delete(:clinic)
      slot = described_class.from_vaos_slot(vaos_slot)

      expect(slot.clinic_ien).to be_nil
    end
  end
end
