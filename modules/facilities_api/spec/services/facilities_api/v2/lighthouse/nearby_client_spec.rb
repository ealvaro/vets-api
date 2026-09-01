# frozen_string_literal: true

require 'rails_helper'

vcr_options = {
  cassette_name: 'facilities/va/nearby',
  match_requests_on: %i[path query]
}

RSpec.describe FacilitiesApi::V2::Lighthouse::NearbyClient, team: :facilities, vcr: vcr_options do
  let(:nearby_client) { described_class.new }

  describe '#nearby' do
    it 'returns nearby facilities with parsed drive-time bands' do
      facilities = nearby_client.nearby(lat: 40.7128, long: -74.006)

      expect(facilities).to all(be_a(FacilitiesApi::V2::Lighthouse::NearbyFacility))
      expect(facilities.map(&:id)).to eq(%w[vha_630 vha_526GD vha_561GE])
      expect(facilities.first).to have_attributes(id: 'vha_630', min_time: 10, max_time: 20)
    end
  end

  describe 'breaker isolation' do
    # The point of this client existing at all: /nearby must not share the breaker that
    # guards /facilities, since /facilities produces the VA provider list that drive-time
    # enrichment decorates.
    it 'uses its own breakers service name, distinct from the facilities client' do
      expect(described_class.configuration.service_name).to eq('Lighthouse_Facilities_Nearby')
      expect(described_class.configuration.service_name)
        .not_to eq(FacilitiesApi::V2::Lighthouse::Client.configuration.service_name)
    end

    # The breaker name is deliberately NOT reused as the RaiseCustomError prefix:
    # exception keys are looked up in config/locales/exceptions.en.yml, and a
    # LIGHTHOUSE_FACILITIES_NEARBY* key has no entry there.
    it 'keeps the shared error prefix so backend exceptions still resolve to locale keys' do
      prefix = described_class.configuration.error_prefix

      expect(prefix).to eq('Lighthouse_Facilities')
      expect(I18n.exists?("common.exceptions.#{prefix.upcase}400")).to be(true)
    end
  end
end
