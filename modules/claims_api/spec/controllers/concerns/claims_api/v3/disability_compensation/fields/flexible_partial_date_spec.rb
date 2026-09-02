# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ClaimsApi::V3::DisabilityCompensation::Fields::FlexiblePartialDate, type: :model do
  let(:errors) { ClaimsApi::V3::DisabilityCompensation::Errors.new }

  describe '.call' do
    context 'when the value is nil' do
      it 'adds no errors' do
        described_class.call(nil, source: '/approximateDate', errors:)

        expect(errors.any?).to be(false)
      end
    end

    context 'when the value is a future date' do
      %w[2099-05-15 2099-05 2099].each do |value|
        it "adds a 'must be in the past' error for #{value}" do
          described_class.call(value, source: '/approximateDate', errors:)

          expect(errors.messages.size).to eq(1)
          expect(errors.messages.first).to include(
            source: '/approximateDate',
            detail: 'approximateDate must be a date in the past.'
          )
        end
      end
    end

    context 'when the value is not a real calendar date' do
      it 'adds a "not a valid date" error' do
        described_class.call('2018-02-31', source: '/approximateDate', errors:)
        expect(errors.messages.size).to eq(1)
        expect(errors.messages.first).to include(
          source: '/approximateDate',
          detail: '2018-02-31 is not a valid date.'
        )
      end
    end
  end
end
