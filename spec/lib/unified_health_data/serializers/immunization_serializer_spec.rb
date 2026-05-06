# frozen_string_literal: true

require 'rails_helper'
require 'unified_health_data/models/immunization'
require 'unified_health_data/serializers/immunization_serializer'

RSpec.describe UnifiedHealthData::Serializers::ImmunizationSerializer do
  let(:immunization) do
    UnifiedHealthData::Immunization.new(
      id: 'imm-123',
      cvx_code: 207,
      date: '2025-01-15T09:00:00Z',
      dose_number: '1',
      dose_series: '2',
      group_name: 'COVID-19',
      location: 'VA Medical Center',
      manufacturer: 'Moderna',
      note: 'No adverse reaction observed.',
      reaction: 'None',
      short_description: 'COVID-19 mRNA vaccine',
      administration_site: 'Left arm',
      lot_number: 'ABC1234',
      status: 'completed'
    )
  end

  describe '.new' do
    it 'returns correct JSONAPI structure with all attributes' do
      result = described_class.new(immunization).serializable_hash[:data]

      expect(result[:id]).to eq('imm-123')
      expect(result[:type]).to eq(:immunization)
      expect(result[:attributes]).to include(
        cvx_code: 207,
        date: '2025-01-15T09:00:00Z',
        dose_number: '1',
        dose_series: '2',
        group_name: 'COVID-19',
        location: 'VA Medical Center',
        manufacturer: 'Moderna',
        note: 'No adverse reaction observed.',
        reaction: 'None',
        short_description: 'COVID-19 mRNA vaccine',
        administration_site: 'Left arm',
        lot_number: 'ABC1234',
        status: 'completed'
      )
    end

    it 'handles array of immunizations' do
      immunizations = [immunization, immunization]
      result = described_class.new(immunizations).serializable_hash[:data]

      expect(result).to be_an(Array)
      expect(result.size).to eq(2)
      expect(result.first[:type]).to eq(:immunization)
    end

    it 'handles nil optional fields' do
      minimal_immunization = UnifiedHealthData::Immunization.new(
        id: 'imm-456',
        short_description: 'Flu vaccine'
      )
      result = described_class.new(minimal_immunization).serializable_hash[:data]

      expect(result[:id]).to eq('imm-456')
      expect(result[:attributes][:short_description]).to eq('Flu vaccine')
      expect(result[:attributes][:manufacturer]).to be_nil
      expect(result[:attributes][:lot_number]).to be_nil
      expect(result[:attributes][:reaction]).to be_nil
    end
  end
end
