# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ClaimsApi::V3::DisabilityCompensation::Sections::ServiceInformation, type: :unit do
  def validate(payload)
    described_class.new(payload).validate
  end

  it 'returns empty errors for blank payload' do
    result = validate({})
    expect(result.any?).to be(false)
  end

  it 'returns a plain Array (new contract)' do
    result = validate({})
    expect(result).to be_an(Array)
  end

  it 'returns no errors for a valid payload' do
    result = validate(
      'servicePeriods' => [
        { 'entryDate' => '2010-01-01', 'exitDate' => '2014-01-01',
          'serviceBranch' => 'ARMY', 'component' => ['Active'] }
      ]
    )
    expect(result.any?).to be(false)
  end

  it 'collects date ordering errors' do
    result = validate(
      'servicePeriods' => [
        { 'entryDate' => '2015-01-01', 'exitDate' => '2014-01-01' }
      ]
    )
    expect(result.any? { |e| e[:detail].include?('exitDate') }).to be(true)
  end

  it 'prepends /serviceInformation to all sources' do
    result = validate(
      'servicePeriods' => [
        { 'entryDate' => '2015-01-01', 'exitDate' => '2014-01-01' }
      ]
    )
    result.each do |msg|
      expect(msg[:source]).to start_with('/serviceInformation')
    end
  end

  it 'returns empty errors when servicePeriods is blank' do
    result = validate('servicePeriods' => nil)
    expect(result.any?).to be(false)
  end

  context 'service periods quantity' do
    it 'validates max service periods' do
      periods = Array.new(101) do
        { 'entryDate' => '2010-01-01', 'exitDate' => '2014-01-01' }
      end
      result = validate('servicePeriods' => periods)
      expect(result.any? { |e| e[:detail].include?('101') }).to be(true)
    end
  end
end
