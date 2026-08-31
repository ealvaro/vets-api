# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ClaimsApi::V3::DisabilityCompensation::Fields::ClaimDate, type: :unit do
  let(:source) { '/claimDate' }

  describe '#validate' do
    context 'when raw_field is nil' do
      it 'defaults to Date.current' do
        result = described_class.new(nil, source:).validate
        expect(result).to eq(Date.current)
      end
    end

    context 'when raw_field is an empty string' do
      it 'defaults to Date.current' do
        result = described_class.new('', source:).validate
        expect(result).to eq(Date.current)
      end
    end

    context 'when raw_field is a valid YYYY-MM-DD date' do
      it 'returns the parsed date' do
        result = described_class.new('2020-01-01', source:).validate
        expect(result).to eq(Date.new(2020, 1, 1))
      end
    end

    context 'when raw_field has a timestamp' do
      it 'returns the parsed date portion' do
        result = described_class.new('2020-01-01T12:00:00Z', source:).validate
        expect(result).to eq(Date.new(2020, 1, 1))
      end
    end

    context 'when raw_field is Feb 29 on a leap year' do
      it 'returns the parsed date' do
        result = described_class.new('2024-02-29', source:).validate
        expect(result).to eq(Date.new(2024, 2, 29))
      end
    end

    shared_examples 'an invalid date that raises' do |invalid_date|
      it 'raises a JsonFormValidationError with a "not a valid date" detail' do
        expect { described_class.new(invalid_date, source:).validate }
          .to raise_error(ClaimsApi::Common::Exceptions::Lighthouse::JsonFormValidationError) do |error|
            expect(error.errors_array.first[:detail]).to eq("#{invalid_date} is not a valid date.")
            expect(error.errors_array.first[:source]).to eq(pointer: "data/attributes#{source}")
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

      it 'rescues the TypeError and raises a JsonFormValidationError' do
        expect { described_class.new(non_string_date, source:).validate }
          .to raise_error(ClaimsApi::Common::Exceptions::Lighthouse::JsonFormValidationError) do |error|
            expect(error.errors_array.first[:detail]).to eq("#{non_string_date} is not a valid date.")
          end
      end
    end
  end
end
