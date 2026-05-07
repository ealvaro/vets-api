# frozen_string_literal: true

require 'rails_helper'

describe IvcChampva::FileNaming do
  describe 'constants' do
    it 'defines COMBINED_PDF_SUFFIX' do
      expect(described_class::COMBINED_PDF_SUFFIX).to eq('_combined.pdf')
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
