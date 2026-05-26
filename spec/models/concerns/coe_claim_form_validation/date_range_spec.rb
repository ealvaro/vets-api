# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CoeClaimFormValidation::DateRange do
  subject(:host) { date_range_host.new }

  let(:date_range_host) do
    Class.new do
      include ActiveModel::Model
      include ActiveModel::Validations
      include CoeClaimFormValidation::Helpers
      include CoeClaimFormValidation::DateRange
    end
  end

  describe '#validate_coe_date_range' do
    it 'requires dateRange when blank' do
      host.send(:validate_coe_date_range, nil, '/base')
      expect(host.errors['/base/dateRange']).to include('is required')
    end

    it 'requires dateRange to be an object' do
      host.send(:validate_coe_date_range, 'nope', '/base')
      expect(host.errors['/base/dateRange']).to include('must be an object')
    end

    it 'accepts a valid range without optional to' do
      dr = { 'from' => '2000-01-01T00:00:00Z' }
      host.send(:validate_coe_date_range, dr, '/base')
      expect(host.errors).to be_empty
    end

    it 'requires from to be present' do
      host.send(:validate_coe_date_range, { 'from' => '' }, '/base')
      expect(host.errors['/base/dateRange/from']).to include('is required')
    end

    it 'rejects from when it is not a string' do
      host.send(:validate_coe_date_range, { 'from' => 123 }, '/base')
      expect(host.errors['/base/dateRange/from']).to include('must be a string')
    end

    it 'rejects an invalid from date with the format error message' do
      host.send(:validate_coe_date_range, { 'from' => 'not-a-date' }, '/base')
      expect(host.errors['/base/dateRange/from'])
        .to include(CoeClaimFormValidation::COE_DATE_RANGE_STRING_FORMAT_MESSAGE)
    end

    it 'rejects to when present but not a string' do
      dr = { 'from' => '2000-01-01T00:00:00Z', 'to' => 123 }
      host.send(:validate_coe_date_range, dr, '/base')
      expect(host.errors['/base/dateRange/to']).to include('must be a string')
    end

    it 'rejects an invalid to date' do
      dr = { 'from' => '2000-01-01T00:00:00Z', 'to' => 'bogus' }
      host.send(:validate_coe_date_range, dr, '/base')
      expect(host.errors['/base/dateRange/to'])
        .to include(CoeClaimFormValidation::COE_DATE_RANGE_STRING_FORMAT_MESSAGE)
    end

    it 'rejects to before from when both dates are valid' do
      dr = {
        'from' => '2005-01-01T00:00:00.000Z',
        'to' => '2000-01-01T00:00:00.000Z'
      }
      host.send(:validate_coe_date_range, dr, '/base')
      expect(host.errors['/base/dateRange/to']).to include('must be on or after from')
    end

    it 'skips optional to validation when to is blank' do
      dr = { 'from' => '2000-01-01T00:00:00Z', 'to' => '' }
      host.send(:validate_coe_date_range, dr, '/base')
      expect(host.errors['/base/dateRange/to']).to be_empty
    end

    it 'skips optional to validation when the to key is absent' do
      dr = { 'from' => '2000-01-01T00:00:00Z' }
      host.send(:validate_coe_date_range, dr, '/base')
      expect(host.errors['/base/dateRange/to']).to be_empty
    end
  end
end
