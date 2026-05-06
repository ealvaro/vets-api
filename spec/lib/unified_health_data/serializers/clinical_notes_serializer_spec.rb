# frozen_string_literal: true

require 'rails_helper'
require 'unified_health_data/models/clinical_notes'
require 'unified_health_data/serializers/clinical_notes_serializer'

RSpec.describe UnifiedHealthData::Serializers::ClinicalNotesSerializer do
  let(:clinical_note) do
    UnifiedHealthData::ClinicalNotes.new(
      id: 'note-123',
      name: 'Cardiology Consult',
      note_type: 'consult',
      loinc_codes: ['11488-4'],
      date: '2025-04-10T14:30:00Z',
      date_signed: '2025-04-10T16:00:00Z',
      written_by: 'Dr. Smith, John',
      signed_by: 'Dr. Smith, John',
      admission_date: '2025-04-09T08:00:00Z',
      discharge_date: '2025-04-11T10:00:00Z',
      location: 'VA Medical Center',
      note: 'U29tZSBiYXNlNjQgZW5jb2RlZCBub3Rl',
      addenda: [{ date: '2025-04-11T09:00:00Z', note: 'Follow-up needed.' }],
      source: 'vista'
    )
  end

  describe '.new' do
    it 'returns correct JSONAPI structure with all attributes' do
      result = described_class.new(clinical_note).serializable_hash[:data]

      expect(result[:id]).to eq('note-123')
      expect(result[:type]).to eq(:clinical_note)
      expect(result[:attributes]).to include(
        id: 'note-123',
        name: 'Cardiology Consult',
        note_type: 'consult',
        loinc_codes: ['11488-4'],
        date: '2025-04-10T14:30:00Z',
        date_signed: '2025-04-10T16:00:00Z',
        written_by: 'Dr. Smith, John',
        signed_by: 'Dr. Smith, John',
        admission_date: '2025-04-09T08:00:00Z',
        discharge_date: '2025-04-11T10:00:00Z',
        location: 'VA Medical Center',
        note: 'U29tZSBiYXNlNjQgZW5jb2RlZCBub3Rl',
        addenda: [{ date: '2025-04-11T09:00:00Z', note: 'Follow-up needed.' }],
        source: 'vista'
      )
    end

    it 'handles array of clinical notes' do
      notes = [clinical_note, clinical_note]
      result = described_class.new(notes).serializable_hash[:data]

      expect(result).to be_an(Array)
      expect(result.size).to eq(2)
      expect(result.first[:type]).to eq(:clinical_note)
    end

    it 'handles nil optional fields' do
      minimal_note = UnifiedHealthData::ClinicalNotes.new(
        id: 'note-456',
        name: 'Progress Note'
      )
      result = described_class.new(minimal_note).serializable_hash[:data]

      expect(result[:id]).to eq('note-456')
      expect(result[:attributes][:name]).to eq('Progress Note')
      expect(result[:attributes][:addenda]).to be_nil
      expect(result[:attributes][:signed_by]).to be_nil
      expect(result[:attributes][:source]).to be_nil
    end

    it 'includes meta warnings when passed as options' do
      warnings = ['Oracle Health data source temporarily unavailable']
      opts = { meta: { warnings: } }
      notes = [clinical_note]
      result = described_class.new(notes, opts).serializable_hash

      expect(result[:data].size).to eq(1)
      expect(result[:meta]).to eq({ warnings: })
    end

    it 'does not include meta when no options are passed' do
      result = described_class.new([clinical_note]).serializable_hash

      expect(result[:meta]).to be_nil
    end
  end
end
