# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CoeClaimFormValidation::Helpers do
  subject(:host) { helper_host.new }

  let(:helper_host) do
    Class.new do
      include ActiveModel::Model
      include ActiveModel::Validations
      include CoeClaimFormValidation::Helpers
    end
  end

  describe '#validate_required_string' do
    it 'adds an error when value is blank' do
      host.send(:validate_required_string, '', '/x')
      expect(host.errors['/x']).to include('is required')
    end

    it 'adds an error when value is not a string' do
      host.send(:validate_required_string, 1, '/x')
      expect(host.errors['/x']).to include('must be a string')
    end

    it 'does not add errors for a non-blank string' do
      host.send(:validate_required_string, 'ok', '/x')
      expect(host.errors).to be_empty
    end
  end

  describe '#validate_optional_string' do
    it 'returns without error when value is blank' do
      host.send(:validate_optional_string, nil, '/x')
      host.send(:validate_optional_string, '', '/x')
      expect(host.errors).to be_empty
    end

    it 'adds an error when value is present but not a string' do
      host.send(:validate_optional_string, 99, '/x')
      expect(host.errors['/x']).to include('must be a string')
    end
  end

  describe '#validate_required_string_enum' do
    it 'requires a value' do
      host.send(:validate_required_string_enum, '', '/x', %w[a])
      expect(host.errors['/x']).to include('is required')
    end

    it 'rejects non-strings' do
      host.send(:validate_required_string_enum, 1, '/x', %w[a])
      expect(host.errors['/x']).to include('must be a string')
    end

    it 'rejects values not in the allowed list' do
      host.send(:validate_required_string_enum, 'b', '/x', %w[a])
      expect(host.errors['/x']).to include('is not a valid value')
    end
  end

  describe '#validate_required_or_object_error' do
    it 'adds required when blank' do
      host.send(:validate_required_or_object_error, nil, '/x')
      expect(host.errors['/x']).to include('is required')
    end

    it 'adds object error when present but not a hash' do
      host.send(:validate_required_or_object_error, 'nope', '/x')
      expect(host.errors['/x']).to include('must be an object')
    end
  end

  describe '#validate_postal_code' do
    it 'adds an error for an invalid postal code string' do
      host.send(:validate_postal_code, '1234', '/x')
      expect(host.errors['/x'].join).to include('postal code')
    end

    it 'does not add an error for blank or non-string' do
      host.send(:validate_postal_code, nil, '/x')
      host.send(:validate_postal_code, '', '/x')
      host.send(:validate_postal_code, 12_345, '/x')
      expect(host.errors).to be_empty
    end
  end

  describe '#validate_state_code' do
    it 'skips validation for blank or non-string' do
      host.send(:validate_state_code, nil, '/x')
      host.send(:validate_state_code, '', '/x')
      host.send(:validate_state_code, 1, '/x')
      expect(host.errors).to be_empty
    end

    it 'adds an error for an unknown state code' do
      host.send(:validate_state_code, 'ZZ', '/x')
      expect(host.errors['/x']).to include('is not a valid state code')
    end
  end

  describe '#validate_booleanish_field' do
    it 'adds required when value is missing' do
      host.send(:validate_booleanish_field, nil, '/x')
      expect(host.errors['/x']).to include('is required')
    end

    it 'adds required when string is only whitespace' do
      host.send(:validate_booleanish_field, '   ', '/x')
      expect(host.errors['/x']).to include('is required')
    end

    it 'rejects values that are not booleanish' do
      host.send(:validate_booleanish_field, 'maybe', '/x')
      expect(host.errors['/x']).to include('must be true or false')
    end

    it 'accepts boolean and string forms' do
      %w[true false True FALSE].each do |v|
        h = helper_host.new
        h.send(:validate_booleanish_field, v, '/x')
        expect(h.errors).to be_empty
      end
      h = helper_host.new
      h.send(:validate_booleanish_field, true, '/x')
      expect(h.errors).to be_empty
      h = helper_host.new
      h.send(:validate_booleanish_field, false, '/x')
      expect(h.errors).to be_empty
    end
  end

  describe '#coe_date_string_valid?' do
    it 'returns false for blank or non-string' do
      expect(host.send(:coe_date_string_valid?, nil)).to be false
      expect(host.send(:coe_date_string_valid?, '')).to be false
      expect(host.send(:coe_date_string_valid?, 1)).to be false
    end

    it 'returns true for strings matching the DOB pattern' do
      expect(host.send(:coe_date_string_valid?, '2000-01-01')).to be true
    end

    it 'returns true for parseable ISO8601 strings' do
      expect(host.send(:coe_date_string_valid?, '2000-01-01T00:00:00Z')).to be true
    end

    it 'returns false when iso8601 parsing raises ArgumentError' do
      expect(host.send(:coe_date_string_valid?, 'not-a-date')).to be false
    end
  end
end
