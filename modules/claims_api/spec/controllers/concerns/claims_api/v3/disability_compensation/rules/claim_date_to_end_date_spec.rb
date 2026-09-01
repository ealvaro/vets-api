# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ClaimsApi::V3::DisabilityCompensation::Rules::ClaimDateToEndDate, type: :unit do
  def errors
    @errors ||= ClaimsApi::V3::DisabilityCompensation::Errors.new
  end

  let(:claim_date) { Date.new(2025, 1, 15) }

  it 'adds no errors when exitDate is within 180 days of claim date' do
    periods = [{ 'entryDate' => '2020-01-01', 'exitDate' => '2025-06-01',
                 'component' => ['Active'] }]
    described_class.call(periods, claim_date:, errors:)
    expect(errors.any?).to be(false)
  end

  it 'adds an error when exitDate is beyond 180 days from claim date' do
    periods = [{ 'entryDate' => '2020-01-01', 'exitDate' => '2026-06-01',
                 'component' => ['Active'] }]
    described_class.call(periods, claim_date:, errors:)
    expect(errors.messages.size).to eq(1)
    expect(errors.messages.first[:detail]).to include('within 180 days')
  end

  it 'allows future exitDate for reserves with a past service period' do
    periods = [
      { 'entryDate' => '2015-01-01', 'exitDate' => '2019-06-01',
        'component' => ['Active'] },
      { 'entryDate' => '2020-01-01', 'exitDate' => '2026-06-01',
        'component' => ['Reserves'] }
    ]
    described_class.call(periods, claim_date:, errors:)
    expect(errors.any?).to be(false)
  end

  it 'adds no errors when exitDate is blank' do
    periods = [{ 'entryDate' => '2020-01-01', 'component' => ['Active'] }]
    described_class.call(periods, claim_date:, errors:)
    expect(errors.any?).to be(false)
  end

  it 'adds no errors when claim_date is nil' do
    periods = [{ 'entryDate' => '2020-01-01', 'exitDate' => '2026-06-01' }]
    described_class.call(periods, claim_date: nil, errors:)
    expect(errors.any?).to be(false)
  end
end
