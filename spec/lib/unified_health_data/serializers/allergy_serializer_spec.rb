# frozen_string_literal: true

require 'rails_helper'
require 'unified_health_data/models/allergy'
require 'unified_health_data/serializers/allergy_serializer'

RSpec.describe UnifiedHealthData::Serializers::AllergySerializer do
  let(:allergy) do
    UnifiedHealthData::Allergy.new(
      id: 'allergy-123',
      name: 'Penicillin',
      date: '2025-03-10T08:00:00Z',
      categories: ['medication'],
      reactions: %w[hives rash],
      location: 'VA Medical Center',
      observedHistoric: 'o',
      notes: ['Patient reported mild reaction.'],
      provider: 'Dr. Jones, Mary'
    )
  end

  describe '.new' do
    it 'returns correct JSONAPI structure with all attributes' do
      result = described_class.new(allergy).serializable_hash[:data]

      expect(result[:id]).to eq('allergy-123')
      expect(result[:type]).to eq(:allergy)
      expect(result[:attributes]).to include(
        id: 'allergy-123',
        name: 'Penicillin',
        date: '2025-03-10T08:00:00Z',
        categories: ['medication'],
        reactions: %w[hives rash],
        location: 'VA Medical Center',
        observedHistoric: 'o',
        notes: ['Patient reported mild reaction.'],
        provider: 'Dr. Jones, Mary'
      )
    end

    it 'handles array of allergies' do
      allergies = [allergy, allergy]
      result = described_class.new(allergies).serializable_hash[:data]

      expect(result).to be_an(Array)
      expect(result.size).to eq(2)
      expect(result.first[:type]).to eq(:allergy)
    end

    it 'handles nil optional fields' do
      minimal_allergy = UnifiedHealthData::Allergy.new(
        id: 'allergy-456',
        name: 'Latex'
      )
      result = described_class.new(minimal_allergy).serializable_hash[:data]

      expect(result[:id]).to eq('allergy-456')
      expect(result[:attributes][:name]).to eq('Latex')
      expect(result[:attributes][:observedHistoric]).to be_nil
      expect(result[:attributes][:provider]).to be_nil
    end
  end
end
