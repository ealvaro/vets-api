# frozen_string_literal: true

require 'rails_helper'
require 'unified_health_data/models/lab_or_test'
require 'unified_health_data/serializers/lab_or_test_serializer'

RSpec.describe UnifiedHealthData::Serializers::LabOrTestSerializer do
  let(:lab_or_test) do
    UnifiedHealthData::LabOrTest.new(
      id: 'lab-123',
      display: 'Complete Blood Count',
      test_code: '58410-2',
      test_code_display: 'CBC panel',
      date_completed: '2025-02-20T11:00:00Z',
      sample_tested: 'Blood',
      encoded_data: 'base64data',
      location: 'VA Medical Center',
      ordered_by: 'Dr. Williams, Sarah',
      body_site: 'Left arm',
      comments: ['Fasting sample.'],
      status: 'final',
      source: 'vista',
      facility_timezone: 'America/New_York',
      observations: []
    )
  end

  describe '.new' do
    it 'returns correct JSONAPI structure with all attributes' do
      result = described_class.new(lab_or_test).serializable_hash[:data]

      expect(result[:id]).to eq('lab-123')
      expect(result[:type]).to eq(:DiagnosticReport)
      expect(result[:attributes]).to include(
        display: 'Complete Blood Count',
        test_code: '58410-2',
        test_code_display: 'CBC panel',
        date_completed: '2025-02-20T11:00:00Z',
        sample_tested: 'Blood',
        encoded_data: 'base64data',
        location: 'VA Medical Center',
        ordered_by: 'Dr. Williams, Sarah',
        body_site: 'Left arm',
        comments: ['Fasting sample.'],
        status: 'final',
        source: 'vista',
        facility_timezone: 'America/New_York',
        observations: []
      )
    end

    it 'handles array of lab or test records' do
      labs = [lab_or_test, lab_or_test]
      result = described_class.new(labs).serializable_hash[:data]

      expect(result).to be_an(Array)
      expect(result.size).to eq(2)
      expect(result.first[:type]).to eq(:DiagnosticReport)
    end

    it 'handles nil optional fields' do
      minimal_lab = UnifiedHealthData::LabOrTest.new(
        id: 'lab-456',
        display: 'Urinalysis'
      )
      result = described_class.new(minimal_lab).serializable_hash[:data]

      expect(result[:id]).to eq('lab-456')
      expect(result[:attributes][:display]).to eq('Urinalysis')
      expect(result[:attributes][:ordered_by]).to be_nil
      expect(result[:attributes][:source]).to be_nil
      expect(result[:attributes][:facility_timezone]).to be_nil
    end

    it 'includes meta warnings when passed as options' do
      warnings = ['Oracle Health data source temporarily unavailable']
      opts = { meta: { warnings: } }
      labs = [lab_or_test]
      result = described_class.new(labs, opts).serializable_hash

      expect(result[:data].size).to eq(1)
      expect(result[:meta]).to eq({ warnings: })
    end

    it 'does not include meta when no options are passed' do
      result = described_class.new([lab_or_test]).serializable_hash

      expect(result[:meta]).to be_nil
    end
  end
end
