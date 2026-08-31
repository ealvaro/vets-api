# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ClaimsApi::V3::DisabilityCompensation::Sections::ClaimDate, type: :unit do
  describe '#validate' do
    context 'when claimDate is missing' do
      it 'adds no errors and returns a defaulted claim_date' do
        claim_date, errors = described_class.new(nil).validate
        expect(errors.any?).to be(false)
        expect(claim_date).to eq(Date.current)
      end
    end

    context 'when claimDate is an empty string' do
      it 'adds no errors and returns a defaulted claim_date' do
        claim_date, errors = described_class.new('').validate
        expect(errors.any?).to be(false)
        expect(claim_date).to eq(Date.current)
      end
    end

    context 'when claimDate is in the past' do
      it 'returns no errors and the parsed claim_date' do
        claim_date, errors = described_class.new('2020-01-01').validate
        expect(errors.any?).to be(false)
        expect(claim_date).to eq(Date.new(2020, 1, 1))
      end
    end

    context 'when claimDate is today' do
      it 'returns no errors' do
        _claim_date, errors = described_class.new(Date.current.to_s).validate
        expect(errors.any?).to be(false)
      end
    end

    context 'when claimDate has a timestamp' do
      it 'returns no errors' do
        _claim_date, errors = described_class.new('2020-01-01T12:00:00Z').validate
        expect(errors.any?).to be(false)
      end
    end

    context 'when claimDate is in the future' do
      it 'adds an error but still returns the parsed claim_date' do
        future_date = (Date.current + 1.day).to_s
        claim_date, errors = described_class.new(future_date).validate
        expect(errors.messages.first[:detail]).to eq('Claim date cannot be in the future')
        expect(claim_date).to eq(Date.parse(future_date))
      end
    end

    context 'when claimDate matches the schema pattern but is not a real calendar date' do
      let(:invalid_date) { '2021-02-30' }

      it 'raises a JsonFormValidationError instead of returning' do
        expect { described_class.new(invalid_date).validate }
          .to raise_error(ClaimsApi::Common::Exceptions::Lighthouse::JsonFormValidationError) do |error|
            expect(error.errors_array.first[:detail]).to eq("#{invalid_date} is not a valid date.")
          end
      end
    end

    # schema validation ensures that claimDate is a valid date string
    context 'when claimDate.to_s does not return a valid date string' do
      let(:non_string_date) { 42 }

      it 'rescues the TypeError and raises a JsonFormValidationError' do
        expect { described_class.new(non_string_date).validate }
          .to raise_error(ClaimsApi::Common::Exceptions::Lighthouse::JsonFormValidationError) do |error|
            expect(error.errors_array.first[:detail]).to eq("#{non_string_date} is not a valid date.")
          end
      end
    end
  end
end
