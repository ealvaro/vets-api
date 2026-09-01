# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ClaimsApi::V3::DisabilityCompensation::Fields::ServiceNumber, type: :unit do
  let(:errors) { ClaimsApi::V3::DisabilityCompensation::Errors.new }
  let(:source) { '/serviceNumber' }

  def validate(value)
    described_class.new(value, source:).validate(errors:)
  end

  it('nil') {
    validate(nil)
    expect(errors.any?).to be(false)
  }

  it('9 chars') {
    validate('123456789')
    expect(errors.any?).to be(false)
  }

  it '10 chars' do
    validate('1234567890')
    expect(errors.messages.first[:detail]).to eq('serviceNumber is too long.')
  end
end
