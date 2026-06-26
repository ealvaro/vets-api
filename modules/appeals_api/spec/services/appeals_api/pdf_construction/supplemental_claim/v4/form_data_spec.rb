# frozen_string_literal: true

require 'rails_helper'

describe AppealsApi::PdfConstruction::SupplementalClaim::V4::FormData do
  describe '#long_evidence_location?' do
    let(:supplemental_claim) { build(:supplemental_claim) }
    let(:form_data) { described_class.new(supplemental_claim) }

    context 'when all locations within the first 3 are at or under the threshold' do
      it 'returns false' do
        allow(form_data).to receive(:new_evidence_locations).and_return(['A' * 200, 'Short location'])
        expect(form_data.long_evidence_location?).to be false
      end
    end

    context 'when a location within the first 3 exceeds the threshold' do
      it 'returns true' do
        allow(form_data).to receive(:new_evidence_locations).and_return(['A' * 201])
        expect(form_data.long_evidence_location?).to be true
      end
    end

    context 'when only a location beyond the first 3 exceeds the threshold' do
      it 'returns false' do
        locations = (['Short'] * 3) + ['A' * 201]
        allow(form_data).to receive(:new_evidence_locations).and_return(locations)
        expect(form_data.long_evidence_location?).to be false
      end
    end
  end
end
