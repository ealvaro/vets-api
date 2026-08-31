# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ClaimsApi::V3::DisabilityCompensation::Form526ValidationOrchestrator, type: :unit do
  let(:valid_countries) { %w[USA Canada] }

  before do
    allow_any_instance_of(described_class).to receive(:valid_countries).and_return(valid_countries)
  end

  describe '#validate' do
    context 'when form_attributes is empty' do
      it 'returns nil' do
        result = described_class.new({}).validate
        expect(result).to be_nil
      end
    end

    describe 'validations with full payload' do
      context 'with a valid payload' do
        it 'returns nil' do
          attrs = {
            'claimDate' => Date.current.to_s,
            'veteranIdentification' => {
              'mailingAddress' => { 'country' => 'USA', 'state' => 'NY', 'zipFirstFive' => '12345' }
            }
          }
          result = described_class.new(attrs).validate
          expect(result).to be_nil
        end
      end

      context 'with validation errors' do
        it 'returns the errors array' do
          attrs = {
            'claimDate' => Date.current.to_s,
            'veteranIdentification' => {
              'mailingAddress' => { 'country' => 'Narnia' },
              'serviceNumber' => '1234567890'
            }
          }
          result = described_class.new(attrs).validate
          expect(result).to be_an(Array)
          expect(result.size).to eq(3)
        end
      end

      context 'with an invalid claimDate' do
        it 'raises a JsonFormValidationError instead of collecting other section errors' do
          attrs = {
            'claimDate' => '2022-13-01',
            'veteranIdentification' => {
              'mailingAddress' => { 'country' => 'Narnia' },
              'serviceNumber' => '1234567890'
            }
          }
          expect { described_class.new(attrs).validate }
            .to raise_error(ClaimsApi::Common::Exceptions::Lighthouse::JsonFormValidationError)
        end
      end
    end

    describe 'validations by section' do
      # claimDate is not required, so stubbing to return an empty errors tuple
      before do
        allow_any_instance_of(described_class).to receive(
          :validate_claim_date
        ).and_return([nil, ClaimsApi::V3::DisabilityCompensation::Errors.new])
      end

      describe 'Claim Date' do
        before do
          allow_any_instance_of(described_class).to receive(
            :validate_claim_date
          ).and_call_original
        end

        context 'with a valid payload' do
          it 'returns nil' do
            attrs = {
              'claimDate' => Date.current.to_s
            }
            result = described_class.new(attrs).validate
            expect(result).to be_nil
          end
        end

        context 'with invalid date in the future' do
          it 'returns the errors array' do
            attrs = {
              'claimDate' => (Date.current + 2.days).to_s
            }
            result = described_class.new(attrs).validate
            expect(result).to be_an(Array)
            expect(result.size).to eq(1)
            expect(result.first[:detail]).to eq('Claim date cannot be in the future')
          end
        end

        context 'with nil claimDate' do
          it 'returns no errors since claimDate falls back to Date.current' do
            attrs = { 'claimDate' => nil }
            result = described_class.new(attrs).validate
            expect(result).to be_nil
          end
        end

        context 'with an invalid claimDate format' do
          it 'raises a JsonFormValidationError' do
            attrs = { 'claimDate' => '2021-02-30' }
            expect { described_class.new(attrs).validate }
              .to raise_error(ClaimsApi::Common::Exceptions::Lighthouse::JsonFormValidationError)
          end
        end
      end

      describe 'Section 1: Veteran Identification' do
        context 'with a valid payload' do
          it 'returns nil' do
            attrs = {
              'veteranIdentification' => {
                'mailingAddress' => { 'country' => 'USA', 'state' => 'NY', 'zipFirstFive' => '12345' }
              }
            }
            result = described_class.new(attrs).validate
            expect(result).to be_nil
          end
        end

        context 'with validation errors' do
          it 'returns the errors array' do
            attrs = {
              'veteranIdentification' => {
                'mailingAddress' => { 'country' => 'Narnia' },
                'serviceNumber' => '1234567890'
              }
            }
            result = described_class.new(attrs).validate
            expect(result).to be_an(Array)
            expect(result.size).to eq(3)
          end
        end

        context 'with nil veteranIdentification' do
          it 'returns nil when section is blank' do
            attrs = { 'veteranIdentification' => nil }
            result = described_class.new(attrs).validate
            expect(result).to be_nil
          end
        end
      end
    end
  end
end
