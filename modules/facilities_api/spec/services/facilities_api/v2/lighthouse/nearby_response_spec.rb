# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FacilitiesApi::V2::Lighthouse::NearbyResponse, team: :facilities do
  subject(:nearby_response) { described_class.new(body, 200) }

  let(:body) do
    {
      'data' => [
        { 'id' => 'vha_630', 'type' => 'nearby_facility', 'attributes' => { 'minTime' => 10, 'maxTime' => 20 } },
        { 'id' => 'vha_526GD', 'type' => 'nearby_facility', 'attributes' => { 'minTime' => 20, 'maxTime' => 30 } }
      ],
      'meta' => { 'bandVersion' => 'JAN2026' }
    }.to_json
  end

  describe '#initialize' do
    it 'parses the body and exposes status and data' do
      expect(nearby_response.status).to eq(200)
      expect(nearby_response.body).to eq(body)
      expect(nearby_response.data.size).to eq(2)
    end

    it 'normalizes a single (non-array) data object into an array' do
      single = { 'data' => { 'id' => 'vha_630', 'attributes' => { 'minTime' => 10, 'maxTime' => 20 } } }.to_json

      expect(described_class.new(single, 200).data.size).to eq(1)
    end

    it 'treats a body with no data key as an empty result' do
      expect(described_class.new({ 'meta' => {} }.to_json, 200).data).to eq([])
    end

    it 'raises on an unparseable body (the caller fails open around it)' do
      expect { described_class.new('not json', 200) }.to raise_error(JSON::ParserError)
    end
  end

  describe '#nearby_facilities' do
    it 'maps each entry to a NearbyFacility with its drive-time band' do
      facilities = nearby_response.nearby_facilities

      expect(facilities).to all(be_a(FacilitiesApi::V2::Lighthouse::NearbyFacility))
      expect(facilities.map(&:id)).to eq(%w[vha_630 vha_526GD])
      expect(facilities.first).to have_attributes(min_time: 10, max_time: 20)
    end

    it 'returns an empty array when the endpoint reports nothing nearby' do
      expect(described_class.new({ 'data' => [] }.to_json, 200).nearby_facilities).to eq([])
    end

    # meta.bandVersion is intentionally not surfaced -- see the note on the class.
    it 'does not expose the response meta' do
      expect(nearby_response).not_to respond_to(:meta)
    end
  end
end
