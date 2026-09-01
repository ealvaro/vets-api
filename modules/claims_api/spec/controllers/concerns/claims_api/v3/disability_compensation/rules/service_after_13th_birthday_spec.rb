# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ClaimsApi::V3::DisabilityCompensation::Rules::ServiceAfter13thBirthday, type: :unit do
  def errors
    @errors ||= ClaimsApi::V3::DisabilityCompensation::Errors.new(base_source: '/serviceInformation')
  end

  let(:birth_date) { Date.new(1990, 6, 15) }

  it 'adds no errors when entryDate is after 13th birthday' do
    described_class.call('2008-01-01', source: '/servicePeriods/0', veteran_birth_date: birth_date, errors:)
    expect(errors.any?).to be(false)
  end

  it 'adds an error when entryDate is before 13th birthday' do
    described_class.call('2000-01-01', source: '/servicePeriods/0', veteran_birth_date: birth_date, errors:)
    expect(errors.messages.size).to eq(1)
    expect(errors.messages.first[:detail]).to include('thirteenth birthday')
  end

  it 'skips when veteran_birth_date is nil' do
    described_class.call('2000-01-01', source: '/servicePeriods/0', veteran_birth_date: nil, errors:)
    expect(errors.any?).to be(false)
  end

  it 'skips when entryDate is blank' do
    described_class.call(nil, source: '/servicePeriods/0', veteran_birth_date: birth_date, errors:)
    expect(errors.any?).to be(false)
  end

  it 'skips when entryDate format is invalid' do
    described_class.call('bad', source: '/servicePeriods/0', veteran_birth_date: birth_date, errors:)
    expect(errors.any?).to be(false)
  end
end
