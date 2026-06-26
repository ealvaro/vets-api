# frozen_string_literal: true

require 'rails_helper'

describe AppealsApi::PdfConstruction::SupplementalClaim::V4::Structure do
  let(:supplemental_claim) { build(:supplemental_claim) }
  let(:structure) { described_class.new(supplemental_claim) }

  describe '#additional_pages?' do
    context 'when a location within the first 3 exceeds the character threshold' do
      it 'returns true' do
        allow(structure.form_data).to receive_messages(
          new_evidence_locations: ['A' * 201],
          contestable_issues: [],
          long_signature?: false
        )
        expect(structure.additional_pages?).to be true
      end
    end

    context 'when all locations are at or under the threshold and count is 3 or fewer' do
      it 'returns false' do
        allow(structure.form_data).to receive_messages(new_evidence_locations: ['Short location'],
                                                       contestable_issues: [], long_signature?: false)
        expect(structure.additional_pages?).to be false
      end
    end
  end

  describe '#fill_evidence_name_location_text' do
    let(:pdf) { Prawn::Document.new }

    context 'when a location exceeds the character threshold' do
      it 'renders the placeholder text instead of the full location' do
        allow(structure.form_data).to receive(:new_evidence_locations).and_return(['A' * 201])
        expect(pdf).to receive(:text_box).with('See attached page for name and location', anything)
        structure.fill_evidence_name_location_text(pdf)
      end
    end

    context 'when a location is at or under the threshold' do
      it 'renders the full location text' do
        location = 'A' * 200
        allow(structure.form_data).to receive(:new_evidence_locations).and_return([location])
        expect(pdf).to receive(:text_box).with(location, anything)
        structure.fill_evidence_name_location_text(pdf)
      end
    end
  end
end
