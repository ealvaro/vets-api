# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ClaimsApi::V3::DisabilityCompensation::Fields::ServicePeriod, type: :unit do
  def errors
    @errors ||= ClaimsApi::V3::DisabilityCompensation::Errors.new(base_source: '/serviceInformation')
  end

  def validate(value)
    described_class.new(value, source: '/servicePeriods/0').validate(errors:)
  end

  context 'invalid date format' do
    it 'adds an error for a calendar-impossible entryDate' do
      validate({ 'entryDate' => '2024-02-30', 'exitDate' => '2025-01-01' })
      expect(errors.messages.any? { |e| e[:detail].include?('2024-02-30') }).to be(true)
    end

    it 'adds an error for a calendar-impossible exitDate' do
      validate({ 'entryDate' => '2020-01-01', 'exitDate' => '2024-06-31' })
      expect(errors.messages.any? { |e| e[:detail].include?('2024-06-31') }).to be(true)
    end
  end

  context 'date ordering' do
    it 'adds no errors when entryDate is before exitDate' do
      validate({ 'entryDate' => '2010-01-01', 'exitDate' => '2014-01-01' })
      expect(errors.any?).to be(false)
    end

    it 'adds an error when entryDate equals exitDate' do
      validate({ 'entryDate' => '2010-01-01', 'exitDate' => '2010-01-01' })
      expect(errors.messages.first[:detail]).to include('exitDate needs to be after entryDate')
    end

    it 'adds an error when entryDate is after exitDate' do
      validate({ 'entryDate' => '2015-01-01', 'exitDate' => '2010-01-01' })
      expect(errors.messages.size).to eq(1)
    end

    it 'skips when entryDate is blank' do
      validate({ 'exitDate' => '2010-01-01' })
      expect(errors.any?).to be(false)
    end

    it 'skips when exitDate is blank' do
      validate({ 'entryDate' => '2010-01-01' })
      expect(errors.any?).to be(false)
    end
  end
end
