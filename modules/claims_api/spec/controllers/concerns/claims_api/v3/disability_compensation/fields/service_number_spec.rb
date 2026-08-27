# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ClaimsApi::V3::DisabilityCompensation::Fields::ServiceNumber, type: :unit do
  let(:errors) { ClaimsApi::V3::DisabilityCompensation::Errors.new }
  let(:source) { '/serviceNumber' }

  it('nil') {
    described_class.call(nil, source:, errors:)
    expect(errors.any?).to be(false)
  }

  it('9 chars') {
    described_class.call('123456789', source:, errors:)
    expect(errors.any?).to be(false)
  }

  it '10 chars' do
    described_class.call('1234567890', source:, errors:)
    expect(errors.messages.first[:detail]).to eq('serviceNumber is too long.')
  end
end
