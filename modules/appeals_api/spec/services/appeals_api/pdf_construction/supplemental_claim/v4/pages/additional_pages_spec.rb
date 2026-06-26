# frozen_string_literal: true

require 'rails_helper'

describe AppealsApi::PdfConstruction::SupplementalClaim::V4::Pages::AdditionalPages do
  let(:supplemental_claim) { create(:extra_supplemental_claim) }
  let(:form_data) { AppealsApi::PdfConstruction::SupplementalClaim::V4::FormData.new(supplemental_claim) }
  let(:pdf) { Prawn::Document.new }
  let(:additional_pages) { described_class.new(pdf, form_data) }

  describe '#build!' do
    it 'returns the same pdf object it received' do
      expect(additional_pages.build!).to eq pdf
    end

    it 'adds a new page' do
      expect { additional_pages.build! }.to change(pdf, :page_count).by 1
    end
  end

  describe '#extra_locations_dates_table_data' do
    context 'when a location within the first 3 exceeds the character threshold' do
      it 'includes that location in the overflow table' do
        long_location = 'A' * 201
        allow(form_data).to receive_messages(new_evidence_locations: [long_location], new_evidence_dates: [[]],
                                             new_evidence_no_dates: [''])

        table_data = additional_pages.send(:extra_locations_dates_table_data)
        expect(table_data).not_to be_nil
        expect(table_data.any? { |row| row.include?(long_location) }).to be true
      end
    end

    context 'when all locations within the first 3 are under the threshold' do
      it 'does not include them in the overflow table' do
        allow(form_data).to receive_messages(new_evidence_locations: ['Short location'], new_evidence_dates: [[]],
                                             new_evidence_no_dates: [''])

        table_data = additional_pages.send(:extra_locations_dates_table_data)
        expect(table_data).to be_nil
      end
    end

    context 'when there are more than 3 locations' do
      it 'includes locations beyond the third in the overflow table' do
        locations = (['Short'] * 3) + ['Fourth location']
        allow(form_data).to receive_messages(new_evidence_locations: locations, new_evidence_dates: [[]] * 4,
                                             new_evidence_no_dates: [''] * 4)

        table_data = additional_pages.send(:extra_locations_dates_table_data)
        expect(table_data.any? { |row| row.include?('Fourth location') }).to be true
      end
    end
  end
end
