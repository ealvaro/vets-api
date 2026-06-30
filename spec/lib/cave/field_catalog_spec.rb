# frozen_string_literal: true

require 'rails_helper'
require 'cave/field_catalog'

RSpec.describe Cave::FieldCatalog do
  describe '.for_ocr_payload' do
    it 'detects a DD-214 payload by its OCR keys' do
      doc = described_class.for_ocr_payload('VETERAN_NAME' => 'JON DOE', 'BRANCH_OF_SERVICE' => 'ARMY')
      expect(doc[:document_name]).to eq('DD-214')
      expect(doc[:artifact_key]).to eq('dd214')
    end

    it 'detects a Death Certificate payload by its DECENDENT_ keys' do
      doc = described_class.for_ocr_payload('DECENDENT_FULL_NAME' => 'JANE DOE')
      expect(doc[:document_name]).to eq('Death Certificate')
      expect(doc[:artifact_key]).to eq('deathCertificates')
    end

    it 'prefers Death Certificate when DECENDENT_ keys are present alongside others' do
      doc = described_class.for_ocr_payload('DECENDENT_FULL_NAME' => 'JANE DOE', 'VETERAN_NAME' => 'JON DOE')
      expect(doc[:document_name]).to eq('Death Certificate')
    end

    it 'returns nil for an unrecognized or empty payload' do
      expect(described_class.for_ocr_payload('FOO' => 'bar')).to be_nil
      expect(described_class.for_ocr_payload({})).to be_nil
      expect(described_class.for_ocr_payload(nil)).to be_nil
    end
  end

  describe '.by_artifact_key' do
    it 'looks up a document type by artifact key' do
      expect(described_class.by_artifact_key('dd214')[:document_name]).to eq('DD-214')
      expect(described_class.by_artifact_key('deathCertificates')[:document_name]).to eq('Death Certificate')
    end

    it 'returns nil for an unknown artifact key' do
      expect(described_class.by_artifact_key('unknown')).to be_nil
    end
  end
end
