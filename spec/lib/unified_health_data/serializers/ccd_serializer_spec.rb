# frozen_string_literal: true

require 'rails_helper'
require 'unified_health_data/models/ccd'
require 'unified_health_data/serializers/ccd_serializer'

RSpec.describe UnifiedHealthData::Serializers::CcdSerializer do
  let(:ccd) do
    UnifiedHealthData::Ccd.new(
      status: 'complete',
      job_id: 'job-abc-123',
      task_id: 'task-456',
      source: 'vista',
      message: 'CCD generation complete',
      retry_after_seconds: 0,
      authored_on: '2025-06-01T12:00:00Z',
      xml: '<ClinicalDocument/>',
      html: '<html><body>CCD</body></html>',
      pdf: 'base64encodedpdf'
    )
  end

  describe '.new' do
    it 'returns correct JSONAPI structure with all attributes' do
      result = described_class.new(ccd).serializable_hash[:data]

      expect(result[:id]).to eq('job-abc-123')
      expect(result[:type]).to eq(:ccd_status)
      expect(result[:attributes]).to include(
        status: 'complete',
        job_id: 'job-abc-123',
        task_id: 'task-456',
        source: 'vista',
        message: 'CCD generation complete',
        retry_after_seconds: 0,
        authored_on: '2025-06-01T12:00:00Z',
        xml: '<ClinicalDocument/>',
        html: '<html><body>CCD</body></html>',
        pdf: 'base64encodedpdf'
      )
    end

    it 'handles nil optional fields' do
      minimal_ccd = UnifiedHealthData::Ccd.new(
        status: 'pending',
        job_id: 'job-789'
      )
      result = described_class.new(minimal_ccd).serializable_hash[:data]

      expect(result[:id]).to eq('job-789')
      expect(result[:type]).to eq(:ccd_status)
      expect(result[:attributes][:status]).to eq('pending')
      expect(result[:attributes][:xml]).to be_nil
      expect(result[:attributes][:html]).to be_nil
      expect(result[:attributes][:pdf]).to be_nil
    end

    it 'handles array of ccd records' do
      ccds = [ccd, ccd]
      result = described_class.new(ccds).serializable_hash[:data]

      expect(result).to be_an(Array)
      expect(result.size).to eq(2)
      expect(result.first[:type]).to eq(:ccd_status)
    end
  end
end
