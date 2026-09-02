# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ClaimsApi::V3::DisabilityCompensation::Sections::ClaimDate, type: :unit do
  describe '#claim_date' do
    it 'exposes the parsed date after #validate is called' do
      section = described_class.new('2020-01-01')
      section.validate
      expect(section.claim_date).to eq(Date.new(2020, 1, 1))
    end
  end

  describe '#validate' do
    context 'when claimDate is missing' do
      it 'returns no errors' do
        errors = described_class.new(nil).validate
        expect(errors).to eq([])
      end
    end

    context 'when claimDate is an empty string' do
      it 'returns no errors' do
        errors = described_class.new('').validate
        expect(errors).to eq([])
      end
    end

    context 'when claimDate is in the past' do
      it 'returns no errors' do
        errors = described_class.new('2020-01-01').validate
        expect(errors).to eq([])
      end
    end

    context 'when claimDate is today' do
      it 'returns no errors' do
        errors = described_class.new(Date.current.to_s).validate
        expect(errors).to eq([])
      end
    end

    context 'when claimDate has a timestamp' do
      it 'returns no errors' do
        errors = described_class.new('2020-01-01T12:00:00Z').validate
        expect(errors).to eq([])
      end
    end

    context 'when claimDate is in the future' do
      it 'adds an error' do
        future_date = (Date.current + 1.day).to_s
        errors = described_class.new(future_date).validate
        expect(errors.first[:detail]).to eq('Claim date cannot be in the future')
      end
    end

    context 'when claimDate matches the schema pattern but is not a real calendar date' do
      let(:invalid_date) { '2021-02-30' }

      it 'raises JsonFormValidationError' do
        expect { described_class.new(invalid_date).validate }.to raise_error(
          ClaimsApi::Common::Exceptions::Lighthouse::JsonFormValidationError
        )
      end
    end

    # schema validation ensures that claimDate is a valid date string
    context 'when claimDate.to_s does not return a valid date string' do
      let(:non_string_date) { 42 }

      it 'raises JsonFormValidationError' do
        expect { described_class.new(non_string_date).validate }.to raise_error(
          ClaimsApi::Common::Exceptions::Lighthouse::JsonFormValidationError
        )
      end
    end
  end
end
