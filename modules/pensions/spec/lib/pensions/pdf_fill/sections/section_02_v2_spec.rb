# frozen_string_literal: true

require 'rails_helper'
require 'pensions/pdf_fill/sections/section_02_v2'

describe Pensions::PdfFill::Section2V2 do
  describe '#handle_street_overflow' do
    subject(:handle_overflow) { described_class.new.send(:handle_street_overflow, address) }

    let(:address) do
      { 'street' => street,
        'street2' => street2,
        'street3' => street3 }
    end
    let(:combined_street) { address.values.compact.join("\n") }

    it 'returns nil if address blank' do
      expect(described_class.new.send(:handle_street_overflow, nil)).to be_nil
    end

    shared_examples 'an address overflow' do
      it 'nullifies street and street2 and overflows combined street into street3' do
        expect { handle_overflow }.to change { address }.from(address).to(
          {
            'street' => nil,
            'street2' => nil,
            'street3' => combined_street
          }
        )
      end
    end

    context 'when street3 not present' do
      let(:street3) { '' }

      context 'when no overflow' do
        let(:street) { '123 Main Street' }
        let(:street2) { 'Rm 5' }

        it 'ensures street3 deleted' do
          expect(street.length).to be < described_class::STREET_LIMIT
          expect(street2.length).to be < described_class::STREET_2_LIMIT
          expect(street3).to eq('')
          handle_overflow
          expect(address).not_to have_key('street3')
        end
      end

      context 'when only one of the two street lines overflow' do
        let(:street) { '123 General Spongebob Squarepants Memorial Parkway' }
        let(:street2) { 'Rm 5' }

        before do
          expect(street.length).to be > described_class::STREET_LIMIT
          expect(street2.length).to be < described_class::STREET_2_LIMIT
        end

        it_behaves_like 'an address overflow'
      end

      context 'when both of the two street lines overflow' do
        let(:street) { '123 General Spongebob Squarepants Memorial Parkway' }
        let(:street2) { 'Attn: Randall' }

        before do
          expect(street.length).to be > described_class::STREET_LIMIT
          expect(street2.length).to be > described_class::STREET_2_LIMIT
        end

        it_behaves_like 'an address overflow'
      end
    end

    context 'when street3 present' do
      let(:street3) { 'Attn: Randall' }

      context 'when no overflow' do
        let(:street) { '123 Main Street' }
        let(:street2) { 'Rm 5' }

        before do
          expect(street.length).to be < described_class::STREET_LIMIT
          expect(street2.length).to be < described_class::STREET_2_LIMIT
        end

        it_behaves_like 'an address overflow'
      end

      context 'when only one of the two street lines overflow' do
        let(:street) { '123 General Spongebob Squarepants Memorial Parkway' }
        let(:street2) { 'Rm 5' }

        before do
          expect(street.length).to be > described_class::STREET_LIMIT
          expect(street2.length).to be < described_class::STREET_2_LIMIT
        end

        it_behaves_like 'an address overflow'
      end

      context 'when both of the two street lines overflow' do
        let(:street) { '123 General Spongebob Squarepants Memorial Parkway' }
        let(:street2) { 'Attn: Randall' }

        before do
          expect(street.length).to be > described_class::STREET_LIMIT
          expect(street2.length).to be > described_class::STREET_2_LIMIT
        end

        it_behaves_like 'an address overflow'
      end
    end
  end
end
