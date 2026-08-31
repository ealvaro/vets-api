# frozen_string_literal: true

require 'rails_helper'

describe IvcChampva::PdfAddressFormatter do
  describe '.format' do
    it 'returns nil for nil' do
      expect(described_class.format(nil)).to be_nil
    end

    context 'when the flag is disabled' do
      before { allow(Flipper).to receive(:enabled?).with(:champva_pdf_address_overflow_fix).and_return(false) }

      it 'preserves legacy behavior, joining lines with the JSON-escaped newline sequence' do
        input = "123 Main St\nApt 4\nBuilding B\nSpringfield, IL\n62701"
        expect(described_class.format(input)).to eq('123 Main St\nApt 4\nBuilding B\nSpringfield, IL\n62701')
      end
    end

    context 'when the flag is enabled' do
      before { allow(Flipper).to receive(:enabled?).with(:champva_pdf_address_overflow_fix).and_return(true) }

      it 'does not condense addresses with 3 or fewer lines' do
        input = "123 Main St\nSpringfield, IL\n62701"
        expect(described_class.format(input)).to eq('123 Main St\nSpringfield, IL\n62701')
      end

      it 'condenses all street lines onto one line so city/state and zip remain visible' do
        input = "123 Main St\nApt 4\nBuilding B\nSpringfield, IL\n62701"
        expect(described_class.format(input)).to eq('123 Main St, Apt 4, Building B\nSpringfield, IL\n62701')
      end
    end
  end
end
