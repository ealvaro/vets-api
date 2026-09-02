# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ClaimsApi::V3::DisabilityCompensation::Sections::ClaimInformation, type: :model do
  let(:brd_lookup) do
    instance_double(
      ClaimsApi::V3::DisabilityCompensation::Services::BrdLookup,
      active_classification_ids: [],
      classification_end_date_for: nil
    )
  end

  describe '#validate' do
    context 'when the payload is nil' do
      it 'returns an empty array' do
        result = described_class.new(nil, brd_lookup:).validate

        expect(result).to eq([])
      end
    end

    context 'when an item has a future approximateDate' do
      it 'adds one error at the item-indexed source' do
        result = described_class.new([{ 'approximateDate' => '2099-01' }], brd_lookup:).validate

        expect(result.size).to eq(1)
        expect(result.first).to include(
          source: '/claimInformation/0/approximateDate',
          detail: 'approximateDate must be a date in the past.'
        )
      end
    end

    context 'when an item has an unknown classificationCode' do
      it 'adds an error at the item-indexed source' do
        allow(brd_lookup).to receive(:active_classification_ids).and_return([9014])

        result = described_class.new(
          [{ 'classificationCode' => '9999' }],
          brd_lookup:
        ).validate

        expect(result.size).to eq(1)
        expect(result.first).to include(
          source: '/claimInformation/0/classificationCode',
          detail: 'classificationCode must match an active code returned from the /disabilities endpoint ' \
                  'of the Benefits Reference Data API.'
        )
      end
    end

    context 'when an item has a future serviceRelevanceExplanation.approximateDate' do
      it 'adds an error at the nested source' do
        result = described_class.new(
          [{ 'serviceRelevanceExplanation' => { 'approximateDate' => '2099-05-15' } }],
          brd_lookup:
        ).validate

        expect(result.size).to eq(1)
        expect(result.first).to include(
          source: '/claimInformation/0/serviceRelevanceExplanation/approximateDate',
          detail: 'approximateDate must be a date in the past.'
        )
      end
    end
  end
end
