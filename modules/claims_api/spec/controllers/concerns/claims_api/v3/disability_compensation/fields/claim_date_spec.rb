# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ClaimsApi::V3::DisabilityCompensation::Fields::ClaimDate, type: :unit do
  let(:source) { '/claimDate' }

  describe '#parse' do
    context 'when raw_field is nil' do
      it 'returns Date.current' do
        value = described_class.new(nil, source:).parse
        expect(value).to eq(Date.current)
      end
    end

    context 'when raw_field is an empty string' do
      it 'returns Date.current' do
        value = described_class.new('', source:).parse
        expect(value).to eq(Date.current)
      end
    end

    context 'when raw_field is a valid YYYY-MM-DD date' do
      it 'returns the parsed date' do
        value = described_class.new('2020-01-01', source:).parse
        expect(value).to eq(Date.new(2020, 1, 1))
      end
    end

    context 'when raw_field has a timestamp' do
      it 'returns the parsed date' do
        value = described_class.new('2020-01-01T12:00:00Z', source:).parse
        expect(value).to eq(Date.new(2020, 1, 1))
      end
    end

    context 'when raw_field is Feb 29 on a leap year' do
      it 'returns the parsed date' do
        value = described_class.new('2024-02-29', source:).parse
        expect(value).to eq(Date.new(2024, 2, 29))
      end
    end
  end

  describe '#validate' do
    it 'does not raise for a valid date' do
      expect { described_class.new('2020-01-01', source:).validate }.not_to raise_error
    end

    shared_examples 'an invalid date that raises' do |invalid_date|
      it 'raises JsonFormValidationError with error details' do
        expect { described_class.new(invalid_date, source:).validate }.to raise_error(
          ClaimsApi::Common::Exceptions::Lighthouse::JsonFormValidationError
        ) do |error|
          expect(error.errors_array.first).to include(
            detail: "#{invalid_date} is not a valid date.",
            source: { pointer: "data/attributes#{source}" }
          )
        end
      end
    end

    context 'when raw_field is not a real calendar date' do
      include_examples 'an invalid date that raises', '2021-02-30'
    end

    context 'when raw_field is Feb 29 on a non-leap year' do
      include_examples 'an invalid date that raises', '2023-02-29'
    end

    context 'when raw_field is the 31st of a 30-day month' do
      include_examples 'an invalid date that raises', '2021-04-31'
    end

    context 'when raw_field does not match ISO8601 format' do
      include_examples 'an invalid date that raises', '08/28/2026'
    end

    context 'when raw_field.to_s does not return a valid date string' do
      let(:non_string_date) { 42 }

      it 'raises JsonFormValidationError with error details' do
        expect { described_class.new(non_string_date, source:).validate }.to raise_error(
          ClaimsApi::Common::Exceptions::Lighthouse::JsonFormValidationError
        ) do |error|
          expect(error.errors_array.first).to include(
            detail: "#{non_string_date} is not a valid date.",
            source: { pointer: "data/attributes#{source}" }
          )
        end
      end
    end
  end
end
