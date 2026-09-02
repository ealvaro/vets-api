# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ClaimsApi::V3::DisabilityCompensation::Rules::ClassificationCodeIsActive, type: :model do
  let(:errors) { ClaimsApi::V3::DisabilityCompensation::Errors.new }
  let(:brd_lookup) { double(:brd_lookup, classification_end_date_for: nil) }

  describe '.call' do
    context 'when the value is nil' do
      it 'adds no errors' do
        described_class.call(nil, source: '/classificationCode', errors:, brd_lookup:)

        expect(errors.any?).to be(false)
      end
    end

    context 'when the value is not in the active classification list' do
      it 'adds a "must match active code" error at the given source' do
        allow(brd_lookup).to receive(:active_classification_ids).and_return([9014, 9020])

        described_class.call('9999', source: '/classificationCode', errors:, brd_lookup:)

        expect(errors.messages.size).to eq(1)
        expect(errors.messages.first).to include(
          source: '/classificationCode',
          detail: 'classificationCode must match an active code returned from the /disabilities endpoint ' \
                  'of the Benefits Reference Data API.'
        )
      end
    end

    context 'when the value is a known but expired classification code' do
      it 'adds a "no longer active" error at the given source' do
        allow(brd_lookup).to receive(:active_classification_ids).and_return([9014])
        allow(brd_lookup).to receive(:classification_end_date_for).with(9014).and_return(Date.new(2020, 1, 1))

        described_class.call('9014', source: '/classificationCode', errors:, brd_lookup:)

        expect(errors.messages.size).to eq(1)
        expect(errors.messages.first).to include(
          source: '/classificationCode',
          detail: 'classificationCode is no longer active.'
        )
      end
    end
  end
end
