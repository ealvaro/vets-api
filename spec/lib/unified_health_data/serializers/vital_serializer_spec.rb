# frozen_string_literal: true

require 'rails_helper'
require 'unified_health_data/models/vital'
require 'unified_health_data/serializers/vital_serializer'

RSpec.describe UnifiedHealthData::Serializers::VitalSerializer do
  let(:vital) do
    UnifiedHealthData::Vital.new(
      id: 'vital-123',
      name: 'Blood Pressure',
      type: 'BLOOD_PRESSURE',
      date: '2025-05-01T10:00:00Z',
      measurement: '120/80 mm[Hg]',
      location: 'VA Medical Center',
      notes: ['Taken while seated.']
    )
  end

  describe '.new' do
    it 'returns correct JSONAPI structure with all attributes' do
      result = described_class.new(vital).serializable_hash[:data]

      expect(result[:id]).to eq('vital-123')
      expect(result[:type]).to eq(:observation)
      expect(result[:attributes]).to include(
        id: 'vital-123',
        name: 'Blood Pressure',
        type: 'BLOOD_PRESSURE',
        date: '2025-05-01T10:00:00Z',
        measurement: '120/80 mm[Hg]',
        location: 'VA Medical Center',
        notes: ['Taken while seated.']
      )
    end

    it 'handles array of vitals' do
      vitals = [vital, vital]
      result = described_class.new(vitals).serializable_hash[:data]

      expect(result).to be_an(Array)
      expect(result.size).to eq(2)
      expect(result.first[:type]).to eq(:observation)
    end

    it 'handles nil optional fields' do
      minimal_vital = UnifiedHealthData::Vital.new(
        id: 'vital-456',
        name: 'Heart Rate'
      )
      result = described_class.new(minimal_vital).serializable_hash[:data]

      expect(result[:id]).to eq('vital-456')
      expect(result[:attributes][:name]).to eq('Heart Rate')
      expect(result[:attributes][:measurement]).to be_nil
      expect(result[:attributes][:location]).to be_nil
      expect(result[:attributes][:notes]).to be_nil
    end
  end
end
