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
        it 'raises JsonFormValidationError instead of validating other sections' do
          attrs = {
            'claimDate' => '2022-13-01',
            'veteranIdentification' => {
              'mailingAddress' => { 'country' => 'Narnia' },
              'serviceNumber' => '1234567890'
            }
          }
          expect { described_class.new(attrs).validate }.to raise_error(
            ClaimsApi::Common::Exceptions::Lighthouse::JsonFormValidationError
          )
        end
      end
    end

    describe 'validations by section' do
      describe 'Claim Date' do
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
          it 'raises JsonFormValidationError' do
            attrs = { 'claimDate' => '2021-02-30' }
            expect { described_class.new(attrs).validate }.to raise_error(
              ClaimsApi::Common::Exceptions::Lighthouse::JsonFormValidationError
            )
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

    context 'with claimInformation errors' do
      it 'surfaces claim information errors in the output' do
        brd_lookup = instance_double(
          ClaimsApi::V3::DisabilityCompensation::Services::BrdLookup,
          active_classification_ids: [],
          classification_end_date_for: nil
        )
        allow(ClaimsApi::V3::DisabilityCompensation::Services::BrdLookup).to receive(:new).and_return(brd_lookup)

        attrs = { 'claimInformation' => [{ 'approximateDate' => '2099-01' }] }
        result = described_class.new(attrs).validate

        expect(result).to be_an(Array)
        expect(result).to include(
          hash_including(
            source: '/claimInformation/0/approximateDate',
            detail: 'approximateDate must be a date in the past.'
          )
        )
      end
    end

    context 'service after 13th birthday (cross-section rule)' do
      it 'adds an error when entryDate is before 13th birthday' do
        attrs = {
          'veteranIdentification' => {
            'dateOfBirth' => '1990-06-15',
            'mailingAddress' => { 'country' => 'USA', 'state' => 'NY', 'zipFirstFive' => '12345' }
          },
          'serviceInformation' => {
            'servicePeriods' => [{ 'entryDate' => '2000-01-01', 'exitDate' => '2004-01-01' }]
          }
        }
        result = described_class.new(attrs).validate
        expect(result).to be_an(Array)
        expect(result.any? { |e| e[:detail].include?('thirteenth birthday') }).to be(true)
      end

      it 'adds no error when entryDate is after 13th birthday' do
        attrs = {
          'veteranIdentification' => {
            'dateOfBirth' => '1990-06-15',
            'mailingAddress' => { 'country' => 'USA', 'state' => 'NY', 'zipFirstFive' => '12345' }
          },
          'serviceInformation' => {
            'servicePeriods' => [{ 'entryDate' => '2010-01-01', 'exitDate' => '2014-01-01' }]
          }
        }
        result = described_class.new(attrs).validate
        expect(result).to be_nil
      end

      it 'skips when dateOfBirth is nil' do
        attrs = {
          'veteranIdentification' => {
            'mailingAddress' => { 'country' => 'USA', 'state' => 'NY', 'zipFirstFive' => '12345' }
          },
          'serviceInformation' => {
            'servicePeriods' => [{ 'entryDate' => '2000-01-01', 'exitDate' => '2004-01-01' }]
          }
        }
        result = described_class.new(attrs).validate
        expect(result).to be_nil
      end

      it 'falls back to auth_headers DOB when form dateOfBirth is nil' do
        attrs = {
          'veteranIdentification' => {
            'mailingAddress' => { 'country' => 'USA', 'state' => 'NY', 'zipFirstFive' => '12345' }
          },
          'serviceInformation' => {
            'servicePeriods' => [{ 'entryDate' => '2000-01-01', 'exitDate' => '2004-01-01' }]
          }
        }
        auth_headers = { 'va_eauth_birthdate' => '1990-06-15' }
        result = described_class.new(attrs, auth_headers:).validate
        expect(result).to be_an(Array)
        expect(result.any? { |e| e[:detail].include?('thirteenth birthday') }).to be(true)
      end
    end
  end
end
