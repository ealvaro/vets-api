# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ClaimsApi::V3::DisabilityCompensation::Fields::Address, type: :unit do
  let(:errors) { ClaimsApi::V3::DisabilityCompensation::Errors.new }
  let(:valid_countries) { %w[USA Canada Japan] }
  let(:source) { '/mailingAddress' }

  def validate(address)
    described_class.new(address, source:).validate(errors:, valid_countries:)
  end

  it 'skips validation when address is empty' do
    validate({})
    expect(errors.any?).to be(false)
  end

  it 'errors on invalid country' do
    validate({ 'country' => 'Narnia' })
    expect(errors.messages.first[:detail]).to eq('The country provided is not valid.')
  end

  context 'when USA' do
    it 'passes with valid fields' do
      validate({ 'country' => 'USA', 'state' => 'NY', 'zipFirstFive' => '12345' })
      expect(errors.any?).to be(false)
    end

    it 'errors when state is missing' do
      validate({ 'country' => 'USA', 'state' => nil, 'zipFirstFive' => '12345' })
      expect(errors.messages.map { |e| e[:source] }).to include("#{source}/state")
    end

    it 'errors when zipFirstFive is missing' do
      validate({ 'country' => 'USA', 'state' => 'NY', 'zipFirstFive' => nil })
      expect(errors.messages.map { |e| e[:source] }).to include("#{source}/zipFirstFive")
    end

    it 'errors when internationalPostalCode is present' do
      validate({ 'country' => 'USA', 'state' => 'NY', 'zipFirstFive' => '12345',
                 'internationalPostalCode' => 'ABC' })
      expect(errors.messages.map { |e| e[:source] }).to include("#{source}/internationalPostalCode")
    end
  end

  context 'when not USA' do
    it 'passes with internationalPostalCode' do
      validate({ 'country' => 'Japan', 'internationalPostalCode' => '1518557' })
      expect(errors.any?).to be(false)
    end

    it 'errors when internationalPostalCode is missing' do
      validate({ 'country' => 'Canada', 'internationalPostalCode' => nil })
      expect(errors.messages.first[:detail])
        .to eq('The internationalPostalCode is required if the country is not USA (international).')
    end
  end
end
