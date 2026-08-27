# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ClaimsApi::V3::DisabilityCompensation::Rules::MilitaryAddressCityStateCoupling, type: :unit do
  let(:errors) { ClaimsApi::V3::DisabilityCompensation::Errors.new }
  let(:source) { '/mailingAddress' }

  it('blank address') {
    described_class.call(nil, source:, errors:)
    expect(errors.any?).to be(false)
  }

  it 'domestic address' do
    described_class.call({ 'city' => 'Portland', 'state' => 'OR' }, source:, errors:)
    expect(errors.any?).to be(false)
  end

  it 'valid military combo' do
    described_class.call({ 'city' => 'APO', 'state' => 'AE' }, source:, errors:)
    expect(errors.any?).to be(false)
  end

  it 'invalid military combo' do
    described_class.call({ 'city' => 'APO', 'state' => 'OR' }, source:, errors:)
    expect(errors.messages.first[:detail]).to eq('Invalid city and military postal combination.')
  end
end
