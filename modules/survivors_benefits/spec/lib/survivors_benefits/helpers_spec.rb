# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SurvivorsBenefits::Helpers do
  subject { dummy_class.new }

  let(:dummy_class) { Class.new { include SurvivorsBenefits::Helpers } }

  describe '#format_date_to_mm_dd_yyyy' do
    it 'formats a valid date string' do
      expect(subject.format_date_to_mm_dd_yyyy('2024-06-01')).to eq('06/01/2024')
    end

    it 'returns nil for blank input' do
      expect(subject.format_date_to_mm_dd_yyyy('')).to be_nil
      expect(subject.format_date_to_mm_dd_yyyy(nil)).to be_nil
    end
  end

  describe '#split_currency_amount_sm' do
    it 'splits a small currency amount correctly' do
      result = subject.split_currency_amount_sm(12_345.67)
      expect(result).to eq({
                             'cents' => '67',
                             'dollars' => '345',
                             'thousands' => '12'
                           })
    end

    it 'returns empty hash for zero, nil, negative, or too large amounts' do
      expect(subject.split_currency_amount_sm(nil)).to eq({})
      expect(subject.split_currency_amount_sm(0)).to eq({})
      expect(subject.split_currency_amount_sm(-1)).to eq({})
      expect(subject.split_currency_amount_sm(1_000_000)).to eq({})
    end

    it 'returns empty hash if any field exceeds its length' do
      result = subject.split_currency_amount_sm(999_999.99, { 'dollars' => 2 })
      expect(result).to eq({})
    end
  end

  describe '#split_currency_amount_lg' do
    it 'splits a large currency amount correctly' do
      result = subject.split_currency_amount_lg(12_345_678.90)
      expect(result).to eq({
                             'cents' => '90',
                             'dollars' => '678',
                             'thousands' => '345',
                             'millions' => '12'
                           })
    end

    it 'returns empty hash for zero, nil, negative, or too large amounts' do
      expect(subject.split_currency_amount_lg(nil)).to eq({})
      expect(subject.split_currency_amount_lg(0)).to eq({})
      expect(subject.split_currency_amount_lg(-1)).to eq({})
      expect(subject.split_currency_amount_lg(99_999_999)).to eq({})
    end

    it 'returns empty hash if any field exceeds its length' do
      result = subject.split_currency_amount_lg(99_999_998.99, { 'thousands' => 2 })
      expect(result).to eq({})
    end
  end

  describe '#get_currency_field' do
    it 'pads value to field length' do
      arr = %w[12 345 678 90]
      expect(subject.get_currency_field(arr, -2, 5)).to eq('  678')
    end

    it 'returns nil if index out of bounds' do
      arr = %w[12 345]
      expect(subject.get_currency_field(arr, -4, 2)).to be_nil
    end
  end

  describe '#change_hash_to_string' do
    it 'joins hash values with spaces' do
      hash = { a: 'foo', b: 'bar', c: 'baz' }
      expect(subject.change_hash_to_string(hash)).to eq('foo bar baz')
    end

    it 'returns empty string for blank hash' do
      expect(subject.change_hash_to_string({})).to eq('')
      expect(subject.change_hash_to_string(nil)).to eq('')
    end
  end

  describe '#signature_field_index_for_claimant_relationship' do
    it 'returns index 0 for the custodian relationship enum value' do
      result = described_class.signature_field_index_for_claimant_relationship('CUSTODIAN_FILING_FOR_CHILD_UNDER_18')

      expect(result).to eq(0)
    end

    it 'returns index 0 for the humanized custodian relationship label' do
      result = described_class.signature_field_index_for_claimant_relationship('CUSTODIAN FILING FOR CHILD UNDER 18')

      expect(result).to eq(0)
    end

    it 'returns index 1 for all non-custodian relationships' do
      expect(described_class.signature_field_index_for_claimant_relationship('SURVIVING_SPOUSE')).to eq(1)
      expect(described_class.signature_field_index_for_claimant_relationship(nil)).to eq(1)
    end
  end

  describe '#format_name' do
    it 'returns a middle initial without changing first and last' do
      result = subject.format_name({
                                     'first' => 'jAnE ann',
                                     'middle' => 'quincy',
                                     'last' => 'doe-smith',
                                     'suffix' => nil
                                   })

      expect(result).to eq({
                             'first' => 'jAnE ann',
                             'middle' => 'Q',
                             'last' => 'doe-smith'
                           })
    end

    it 'uses the first non-space character and upcases middle names' do
      result = subject.format_name({
                                     'first' => 'Jane',
                                     'middle' => '   aNNa   ',
                                     'last' => 'Doe',
                                     'suffix' => nil
                                   })

      expect(result).to eq({
                             'first' => 'Jane',
                             'middle' => 'A',
                             'last' => 'Doe'
                           })
    end

    it 'preserves suffix formatting for Jr. and III' do
      jr_result = subject.format_name({
                                        'first' => 'Jane',
                                        'middle' => 'Q',
                                        'last' => 'Doe',
                                        'suffix' => '  Jr. '
                                      })

      iii_result = subject.format_name({
                                         'first' => 'John',
                                         'middle' => nil,
                                         'last' => 'Doe',
                                         'suffix' => '  III '
                                       })

      expect(jr_result).to eq({
                                'first' => 'Jane',
                                'middle' => 'Q',
                                'last' => 'Doe Jr.'
                              })

      expect(iii_result).to eq({
                                 'first' => 'John',
                                 'middle' => nil,
                                 'last' => 'Doe III'
                               })
    end

    it 'preserves an empty last name when suffix is nil' do
      result = subject.format_name({
                                     'first' => 'Jane',
                                     'middle' => 'Q',
                                     'last' => '',
                                     'suffix' => nil
                                   })

      expect(result).to eq({
                             'first' => 'Jane',
                             'middle' => 'Q',
                             'last' => ''
                           })
    end

    it 'preserves an empty last name when suffix is blank' do
      result = subject.format_name({
                                     'first' => 'Jane',
                                     'middle' => 'Q',
                                     'last' => '',
                                     'suffix' => ' '
                                   })

      expect(result).to eq({
                             'first' => 'Jane',
                             'middle' => 'Q',
                             'last' => ''
                           })
    end
  end
end
