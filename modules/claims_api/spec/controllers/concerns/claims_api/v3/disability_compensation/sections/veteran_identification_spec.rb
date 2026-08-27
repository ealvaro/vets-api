# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ClaimsApi::V3::DisabilityCompensation::Sections::VeteranIdentification, type: :unit do
  let(:valid_countries) { %w[USA Canada Japan] }

  def validate(payload)
    described_class.new(payload, valid_countries:).validate
  end

  it 'returns empty errors for blank payload' do
    result = validate({})
    expect(result.any?).to be(false)
  end

  it 'returns no errors for a valid USA payload' do
    result = validate(
      'mailingAddress' => { 'country' => 'USA', 'state' => 'NY', 'zipFirstFive' => '12345',
                            'city' => 'Schenectady' },
      'serviceNumber' => '12345'
    )
    expect(result.any?).to be(false)
  end

  it 'collects errors from all layers' do
    result = validate(
      'mailingAddress' => { 'country' => 'Narnia' },
      'serviceNumber' => '1234567890'
    )
    # invalid country + intlPostal required (non-USA) + service number too long
    expect(result.messages.size).to eq(3)
  end

  it 'catches invalid military address' do
    result = validate(
      'mailingAddress' => { 'country' => 'USA', 'state' => 'OR', 'zipFirstFive' => '12345', 'city' => 'APO' }
    )
    expect(result.messages.map { |e| e[:detail] }).to include('Invalid city and military postal combination.')
  end

  it 'prepends /veteranIdentification to all sources' do
    result = validate('mailingAddress' => { 'country' => 'Narnia' })
    result.messages.each do |msg|
      expect(msg[:source]).to start_with('/veteranIdentification/')
    end
  end
end
