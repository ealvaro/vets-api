# frozen_string_literal: true

require 'pensions/pdf_fill/helpers'
require 'rails_helper'

describe Pensions::PdfFill::Helpers do
  let(:test_class) do
    Class.new(Pensions::PdfFill::Section) do
      const_set(:STREET_LIMIT, 30)
      const_set(:STREET_2_LIMIT, 5)
    end
  end
  let(:section) { test_class.new }

  describe '#to_radio_yes_no' do
    it 'returns correct values' do
      expect(section.to_radio_yes_no(true)).to eq(0)
      expect(section.to_radio_yes_no(false)).to eq(1)
    end
  end

  describe '#to_checkbox_on_off' do
    context 'when pensions form v2 disabled' do
      it 'returns correct values' do
        allow(Pensions).to receive(:use_v2?).and_return(false)
        expect(section.to_checkbox_on_off(true)).to eq('1')
        expect(section.to_checkbox_on_off(false)).to eq('Off')
      end
    end

    context 'when pensions form v2 enabled' do
      it 'returns correct values' do
        allow(Pensions).to receive(:use_v2?).and_return(true)
        expect(section.to_checkbox_on_off(true)).to eq('Yes')
        expect(section.to_checkbox_on_off(false)).to eq('Off')
      end
    end
  end

  describe '#split_currency_amount' do
    it 'returns correct values' do
      expect(section.split_currency_amount(10_000_000)).to eq({})
      expect(section.split_currency_amount(-1)).to eq({})
      expect(section.split_currency_amount(nil)).to eq({})
      expect(section.split_currency_amount(100)).to eq({
                                                         'part_one' => '100',
                                                         'part_cents' => '00'
                                                       })
      expect(section.split_currency_amount(999_888.77)).to eq({
                                                                'part_two' => '999',
                                                                'part_one' => '888',
                                                                'part_cents' => '77'
                                                              })
      expect(section.split_currency_amount(9_888_777.66)).to eq({
                                                                  'part_three' => '9',
                                                                  'part_two' => '888',
                                                                  'part_one' => '777',
                                                                  'part_cents' => '66'
                                                                })
    end
  end

  describe '#extract_middle_initial' do
    it 'extracts middle initial and updates full name hash' do
      name = { 'first' => 'Spongebob', 'middle' => 'Xanadu', 'last' => 'Squarepants' }
      expect { section.extract_middle_initial(name) }.to change { name['middle'] }
        .from('Xanadu').to('X')
    end

    it 'converts middle name to empty string if middle name blank' do
      name = { 'first' => 'Spongebob', 'last' => 'Squarepants' }
      expect { section.extract_middle_initial(name) }.to change { name['middle'] }
        .from(nil).to('')
    end

    it 'returns full name if full name blank' do
      name = {}
      expect(section.extract_middle_initial(name)).to eq(name)
    end
  end

  describe '#yes?' do
    it 'returns true if form value in default yes values' do
      described_class::DEFAULT_YES_VALUES.each do |value|
        expect(section.yes?(value)).to be true
      end
    end

    it 'returns false if form value not in default yes values' do
      expect(section.yes?('Very True')).to be false
    end
  end

  describe '#to_date_string' do
    it 'returns early if date string cannot be split' do
      expect(section.to_date_string('January 31, 2026')).to be_nil
    end

    it 'formats date' do
      expect(section.to_date_string('2026-01-31')).to eq('01-31-2026')
    end
  end

  describe '#build_date_range_string' do
    let(:range) { { 'from' => '2026-01-31', 'to' => '2027-01-31' } }

    it 'formats from and to dates' do
      expect(section.build_date_range_string(range)).to eq('01-31-2026 - 01-31-2027')
    end

    it 'formats open-ended date range' do
      range.delete('to')
      expect(section.build_date_range_string(range)).to eq('01-31-2026 - No End Date')
    end
  end

  describe '#expand_currency' do
    it 'returns value without formatting if not a float' do
      expect(section.expand_currency(123)).to eq(123)
    end

    it 'stringifies float and preserves trailing zeroes' do
      expect(section.expand_currency(123.50)).to eq('123.50')
    end
  end

  describe '#handle_street_overflow' do
    subject(:handle_street_overflow) { section.handle_street_overflow(address, street_limit, street_2_limit) }

    let(:street_limit) { test_class::STREET_LIMIT }
    let(:street_2_limit) { test_class::STREET_2_LIMIT }
    let(:address) do
      {
        'street' => street,
        'street2' => street2,
        'street3' => street3
      }
    end
    let(:combined_street) { address.values.compact.join("\n") }

    shared_examples 'an address overflow' do
      it 'nullifies street and street2 and overflows combined street into street3' do
        expect { handle_street_overflow }.to change { address }
          .from(address)
          .to(
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
          expect(street.length).to be < street_limit
          expect(street2.length).to be < street_2_limit
          expect(street3).to eq('')
          handle_street_overflow
          expect(address).not_to have_key('street3')
        end
      end

      context 'when only one of the two street lines overflow' do
        let(:street) { '123 General Spongebob Squarepants Memorial Parkway' }
        let(:street2) { 'Rm 5' }

        before do
          expect(street.length).to be > street_limit
          expect(street2.length).to be < street_2_limit
        end

        it_behaves_like 'an address overflow'
      end

      context 'when both of the two street lines overflow' do
        let(:street) { '123 General Spongebob Squarepants Memorial Parkway' }
        let(:street2) { 'Attn: Randall' }

        before do
          expect(street.length).to be > street_limit
          expect(street2.length).to be > street_2_limit
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
          expect(street.length).to be < street_limit
          expect(street2.length).to be < street_2_limit
        end

        it_behaves_like 'an address overflow'
      end

      context 'when only one of the two street lines overflow' do
        let(:street) { '123 General Spongebob Squarepants Memorial Parkway' }
        let(:street2) { 'Rm 5' }

        before do
          expect(street.length).to be > street_limit
          expect(street2.length).to be < street_2_limit
        end

        it_behaves_like 'an address overflow'
      end

      context 'when both of the two street lines overflow' do
        let(:street) { '123 General Spongebob Squarepants Memorial Parkway' }
        let(:street2) { 'Attn: Randall' }

        before do
          expect(street.length).to be > street_limit
          expect(street2.length).to be > street_2_limit
        end

        it_behaves_like 'an address overflow'
      end
    end
  end
end
