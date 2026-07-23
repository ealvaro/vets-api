# frozen_string_literal: true

require 'rails_helper'

describe IvcChampva::FileNaming do
  describe 'constants' do
    it 'defines COMBINED_PDF_SUFFIX' do
      expect(described_class::COMBINED_PDF_SUFFIX).to eq('_combined.pdf')
    end
  end

  describe '.ves_json?' do
    it 'returns true for the 10-10D VES JSON file' do
      expect(described_class.ves_json?('uuid_vha_10_10d_ves.json')).to be true
    end

    it 'returns true for indexed OHI VES JSON files' do
      expect(described_class.ves_json?('uuid_vha_10_7959c_ohi_ves_0.json')).to be true
      expect(described_class.ves_json?('uuid_vha_10_10d_ohi_ves_12.json')).to be true
    end

    it 'returns false for form/supporting-doc/combined PDFs' do
      expect(described_class.ves_json?('uuid_vha_10_10d.pdf')).to be false
      expect(described_class.ves_json?('uuid_vha_10_10d_supporting_doc-0.pdf')).to be false
      expect(described_class.ves_json?('uuid_vha_10_7959f_2_combined.pdf')).to be false
    end

    it 'returns false for the metadata JSON file' do
      expect(described_class.ves_json?('uuid_vha_10_10d_metadata.json')).to be false
    end

    it 'returns false for blank or nil filenames' do
      expect(described_class.ves_json?('')).to be false
      expect(described_class.ves_json?(nil)).to be false
    end
  end

  describe '.combined_pdf?' do
    it 'returns true for _combined.pdf files' do
      expect(described_class.combined_pdf?('uuid_vha_10_7959f_2_combined.pdf')).to be true
    end

    it 'returns false for _merged.pdf files' do
      expect(described_class.combined_pdf?('uuid_vha_10_7959c_medicare_card_0_0_merged.pdf')).to be false
    end

    it 'returns false for regular PDF files' do
      expect(described_class.combined_pdf?('uuid_vha_10_10d.pdf')).to be false
    end

    it 'returns false for blank filenames' do
      expect(described_class.combined_pdf?('')).to be false
    end

    it 'returns false for nil filenames' do
      expect(described_class.combined_pdf?(nil)).to be false
    end
  end
end
