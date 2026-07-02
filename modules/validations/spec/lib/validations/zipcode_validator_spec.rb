# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Validations::Validator::ZipcodeValidator do
  let(:state) { create(:std_state) }

  describe '.validate' do
    context 'with a valid 5-digit zipcode' do
      let!(:valid_zip) { create(:std_zipcode, zip_code: '12345', state_id: state.id) }

      it 'returns valid result' do
        result = described_class.validate('12345')

        expect(result[:zip_is_valid]).to be(true)
        expect(result[:zipcode]).to eq('12345')
        expect(result[:message]).to eq('Valid zipcode')
      end
    end

    context 'with a valid ZIP+4 format' do
      let!(:valid_zip) { create(:std_zipcode, zip_code: '12345', state_id: state.id) }

      it 'extracts the 5-digit part and validates' do
        result = described_class.validate('12345-6789')

        expect(result[:zip_is_valid]).to be(true)
        expect(result[:zipcode]).to eq('12345-6789')
        expect(result[:message]).to eq('Valid zipcode')
      end
    end

    context 'with a blank zipcode' do
      it 'returns invalid result with required message' do
        result = described_class.validate('')

        expect(result[:zip_is_valid]).to be(false)
        expect(result[:message]).to eq('Zipcode is required')
      end
    end

    context 'with nil zipcode' do
      it 'returns invalid result with required message' do
        result = described_class.validate(nil)

        expect(result[:zip_is_valid]).to be(false)
        expect(result[:message]).to eq('Zipcode is required')
      end
    end

    context 'with whitespace-only zipcode' do
      it 'returns invalid result with required message' do
        result = described_class.validate('   ')

        expect(result[:zip_is_valid]).to be(false)
        expect(result[:message]).to eq('Zipcode is required')
      end
    end

    context 'with leading/trailing whitespace' do
      let!(:valid_zip) { create(:std_zipcode, zip_code: '12345', state_id: state.id) }

      it 'normalizes input before validation and echoes normalized zipcode' do
        result = described_class.validate(' 12345 ')

        expect(result[:zip_is_valid]).to be(true)
        expect(result[:zipcode]).to eq('12345')
        expect(result[:message]).to eq('Valid zipcode')
      end
    end

    context 'with too few digits' do
      it 'returns invalid result' do
        result = described_class.validate('1234')

        expect(result[:zip_is_valid]).to be(false)
        expect(result[:message]).to eq('Invalid zipcode')
      end
    end

    context 'with too many digits' do
      it 'returns invalid result' do
        result = described_class.validate('123456')

        expect(result[:zip_is_valid]).to be(false)
        expect(result[:message]).to eq('Invalid zipcode')
      end
    end

    context 'with alphabetic characters' do
      it 'returns invalid result' do
        result = described_class.validate('ABCDE')

        expect(result[:zip_is_valid]).to be(false)
        expect(result[:message]).to eq('Invalid zipcode')
      end
    end

    context 'with special characters' do
      it 'returns invalid result' do
        result = described_class.validate('12@45')

        expect(result[:zip_is_valid]).to be(false)
        expect(result[:message]).to eq('Invalid zipcode')
      end
    end

    context 'with invalid ZIP+4 format' do
      it 'returns invalid result for missing extension digits' do
        result = described_class.validate('12345-123')

        expect(result[:zip_is_valid]).to be(false)
        expect(result[:message]).to eq('Invalid zipcode')
      end

      it 'returns invalid result for too many extension digits' do
        result = described_class.validate('12345-67890')

        expect(result[:zip_is_valid]).to be(false)
        expect(result[:message]).to eq('Invalid zipcode')
      end

      it 'returns invalid result for alphabetic extension' do
        result = described_class.validate('12345-ABCD')

        expect(result[:zip_is_valid]).to be(false)
        expect(result[:message]).to eq('Invalid zipcode')
      end
    end

    context 'with zipcode not in database' do
      it 'returns invalid result' do
        result = described_class.validate('99999')

        expect(result[:zip_is_valid]).to be(false)
        expect(result[:message]).to eq('Zipcode does not exist')
      end
    end

    context 'with zipcode containing spaces' do
      it 'returns invalid result' do
        result = described_class.validate('123 45')

        expect(result[:zip_is_valid]).to be(false)
        expect(result[:message]).to eq('Invalid zipcode')
      end
    end
  end

  describe '#initialize' do
    it 'stores the zipcode' do
      validator = described_class.new('12345')

      expect(validator.send(:zipcode)).to eq('12345')
    end
  end

  describe '#validate' do
    let!(:valid_zip) { create(:std_zipcode, zip_code: '54321', state_id: state.id) }

    it 'returns a hash with zipcode, zip_is_valid, and message keys' do
      validator = described_class.new('54321')
      result = validator.validate

      expect(result).to be_a(Hash)
      expect(result).to include(:zipcode, :zip_is_valid, :message)
    end
  end

  describe '#valid?' do
    context 'when zipcode exists in database' do
      let!(:valid_zip) { create(:std_zipcode, zip_code: '99999', state_id: state.id) }

      it 'returns true' do
        validator = described_class.new('99999')

        expect(validator.send(:valid?)).to be(true)
      end
    end

    context 'when zipcode does not exist in database' do
      it 'returns false' do
        validator = described_class.new('88888')

        expect(validator.send(:valid?)).to be(false)
      end
    end

    context 'with blank zipcode' do
      it 'returns false without querying database' do
        validator = described_class.new('')

        expect(StdZipcode).not_to receive(:distinct)

        expect(validator.send(:valid?)).to be(false)
      end
    end

    context 'with invalid format' do
      it 'returns false without querying database' do
        validator = described_class.new('ABCDE')

        expect(StdZipcode).not_to receive(:distinct)

        expect(validator.send(:valid?)).to be(false)
      end
    end

    context 'with ZIP+4 format' do
      let!(:valid_zip) { create(:std_zipcode, zip_code: '77777', state_id: state.id) }

      it 'uses only the 5-digit part for lookup' do
        validator = described_class.new('77777-1234')

        expect(validator.send(:valid?)).to be(true)
      end
    end

    context 'with cached zipcode list' do
      let!(:valid_zip) { create(:std_zipcode, zip_code: '60606', state_id: state.id) }
      let(:cache_store) { ActiveSupport::Cache::MemoryStore.new }

      before do
        allow(Rails).to receive(:cache).and_return(cache_store)
      end

      it 'does not query StdZipcode on subsequent validations after cache warm' do
        cache_store.clear

        first_validator = described_class.new('60606')
        expect(first_validator.send(:valid?)).to be(true)

        expect(StdZipcode).not_to receive(:distinct)

        second_validator = described_class.new('60606')
        expect(second_validator.send(:valid?)).to be(true)
      end
    end
  end
end
