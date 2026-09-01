# frozen_string_literal: true

require 'rails_helper'

describe FacilitiesApi::V2::Lighthouse::NearbyFacility, team: :facilities, type: :model do
  subject(:facility) { described_class.new(fac) }

  describe '#initialize' do
    context 'with camelCase integer bands' do
      let(:fac) { { 'id' => 'vha_630', 'attributes' => { 'minTime' => 10, 'maxTime' => 20 } } }

      it 'assigns id and drive-time bands' do
        expect(facility).to have_attributes(id: 'vha_630', min_time: 10, max_time: 20)
      end
    end

    context 'with snake_case bands' do
      let(:fac) { { 'id' => 'vha_630', 'attributes' => { 'min_time' => 10, 'max_time' => 20 } } }

      it 'reads the snake_case fallback' do
        expect(facility).to have_attributes(min_time: 10, max_time: 20)
      end
    end

    context 'when the API returns bands as strings' do
      let(:fac) { { 'id' => 'vha_630', 'attributes' => { 'minTime' => '10', 'maxTime' => '20' } } }

      it 'coerces them to Integer via the model setters' do
        expect(facility.min_time).to eq(10)
        expect(facility.max_time).to eq(20)
        expect(facility.min_time).to be_a(Integer)
        expect(facility.max_time).to be_a(Integer)
      end
    end

    context 'with missing attributes' do
      let(:fac) { { 'id' => 'vha_630' } }

      it 'leaves the bands nil without raising' do
        expect(facility).to have_attributes(id: 'vha_630', min_time: nil, max_time: nil)
      end
    end
  end
end
