# frozen_string_literal: true

require 'rails_helper'
require 'survivors_benefits/v0/facilities_controller'
require 'support/controller_spec_helper'

RSpec.describe SurvivorsBenefits::V0::FacilitiesController, type: :request do
  let(:facilities_response) { build_list(:lighthouse_facility, 2) }
  let(:state) { 'WA' }
  let(:cache_key) { "VA_health_facilities::#{state}" }

  describe '#index' do
    it 'returns a list of facilities' do
      expect_any_instance_of(SurvivorsBenefits::V0::FacilitiesController)
        .to receive(:cached_facilities)
        .with(cache_key, state)
        .and_return(facilities_response)

      get "/survivors_benefits/v0/facilities/#{state}"

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq(JSON.parse(facilities_response.to_json))
    end
  end

  describe '#cached_facilities' do
    it 'caches the facilities response' do
      client = instance_double(FacilitiesApi::V2::Lighthouse::Client)
      allow(FacilitiesApi::V2::Lighthouse::Client).to receive(:new).and_return(client)
      allow(client).to receive_messages(
        get_facilities: facilities_response,
        class: FacilitiesApi::V2::Lighthouse::Client
      )
      Rails.cache.delete(cache_key)
      expect(Rails.cache).to receive(:fetch).with(cache_key, expires_in: 7.days).and_yield
      expect(client).to receive(:get_facilities)
        .with({ per_page: subject.class::MAX_PER_PAGE, type: 'health', state: })
      subject.send(:cached_facilities, cache_key, state)
    end
  end

  describe '#build_state_filter' do
    it 'returns PH when state is PI' do
      expect(subject.send(:build_state_filter, 'PI')).to eq('PH')
    end

    it 'returns the same state when it is not PI' do
      expect(subject.send(:build_state_filter, 'WA')).to eq('WA')
    end
  end
end
