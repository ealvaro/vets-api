# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ClaimsApi::V3::DisabilityCompensation::Fields::YearMonthDate, type: :model do
  let(:errors) { ClaimsApi::V3::DisabilityCompensation::Errors.new }

  describe '.call' do
    context 'when the value is nil' do
      it 'adds no errors' do
        described_class.call(nil, source: '/approximateDate', errors:)

        expect(errors.any?).to be(false)
      end
    end

    context 'when the value is a future date' do
      it 'adds a "must be in the past" error at the given source' do
        described_class.call('2099-01', source: '/approximateDate', errors:)

        expect(errors.messages.size).to eq(1)
        expect(errors.messages.first).to include(
          source: '/approximateDate',
          detail: 'approximateDate must be a date in the past.'
        )
      end
    end
  end
end
