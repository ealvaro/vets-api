# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CoeClaimFormValidation::MilitaryHistory do
  subject(:host) { military_history_host.new }

  let(:military_history_host) do
    Class.new do
      include ActiveModel::Model
      include ActiveModel::Validations
      include CoeClaimFormValidation::Helpers
      include CoeClaimFormValidation::DateRange

      attr_accessor :parsed_form

      include CoeClaimFormValidation::MilitaryHistory
    end
  end

  let(:valid_period) do
    {
      'serviceBranch' => 'ARMY',
      'dateRange' => {
        'from' => '2000-01-01T00:00:00Z',
        'to' => '2004-01-01T00:00:00Z'
      }
    }
  end

  describe '#validate_military_history' do
    it 'returns early when militaryHistory is not a hash' do
      host.parsed_form = { 'militaryHistory' => 'nope' }
      host.send(:validate_military_history)
      expect(host.errors).to be_empty
    end
  end

  describe '#validate_periods_of_service' do
    it 'returns early when periods is not an array' do
      host.send(:validate_periods_of_service, {})
      expect(host.errors).to be_empty
    end

    it 'requires at least one period' do
      host.send(:validate_periods_of_service, [])
      expect(host.errors['/militaryHistory/periodsOfService'])
        .to include('must include at least one period of service')
    end
  end

  describe '#validate_single_period_of_service' do
    it 'requires each period to be an object' do
      host.send(:validate_single_period_of_service, 'x', 0)
      expect(host.errors['/militaryHistory/periodsOfService/0']).to include('must be an object')
    end

    it 'validates a complete period' do
      host.send(:validate_single_period_of_service, valid_period, 0)
      expect(host.errors).to be_empty
    end
  end
end
