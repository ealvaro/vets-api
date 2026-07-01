# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'RepresentationManagement::V0::AccreditedIndividuals', type: :request do
  let(:path) { '/representation_management/v0/accredited_individuals' }
  let(:type) { 'representative' }
  let(:distance) { 50 }
  let(:lat) { 42.65140884 }
  let(:long) { -73.77623285 }

  context 'when arc_find_a_representative_backend_use_accredited_models is disabled' do
    before do
      allow(Flipper).to receive(:enabled?)
        .with(:arc_find_a_representative_backend_use_accredited_models)
        .and_return(false)
    end

    it 'returns a not found routing error' do
      get path, params: { type:, lat:, long:, distance: }

      parsed_response = JSON.parse(response.body)
      expect(parsed_response['errors'].size).to eq(1)
      expect(parsed_response['errors'][0]['status']).to eq('404')
      expect(parsed_response['errors'][0]['title']).to eq('Not found')
      expect(parsed_response['errors'][0]['detail']).to eq('There are no routes matching your request: ')
    end
  end

  context 'when arc_find_a_representative_backend_use_accredited_models is enabled' do
    before do
      allow(Flipper).to receive(:enabled?)
        .with(:arc_find_a_representative_backend_use_accredited_models)
        .and_return(true)
    end

    context 'when a required param is missing' do
      it 'returns a bad request error' do
        get path, params: { type:, lat: }

        parsed_response = JSON.parse(response.body)
        expect(parsed_response['errors'].size).to eq(1)
        expect(parsed_response['errors'][0]['status']).to eq('400')
        expect(parsed_response['errors'][0]['title']).to eq('Missing parameter')
        expect(parsed_response['errors'][0]['detail']).to eq('The required parameter "long", is missing')
      end
    end

    context 'when the search is invalid' do
      it 'returns a list of the errors and an unprocessable entity error' do
        get path, params: { type: 'abc', lat:, long: -200, distance: 45 }

        parsed_response = JSON.parse(response.body)
        expect(response).to have_http_status(:unprocessable_content)
        expect(parsed_response['errors'].size).to eq(3)
        expect(parsed_response['errors'][0]).to eq('Distance is not included in the list')
        expect(parsed_response['errors'][1]).to eq('Long must be greater than or equal to -180')
        expect(parsed_response['errors'][2]).to eq('Type is not included in the list')
      end
    end

    context 'when the search is valid' do
      let!(:ind1) { create(:accredited_individual, :with_organizations, :with_location, first_name: 'August') }
      let!(:ind2) { create(:accredited_individual, :with_organizations, :with_location, first_name: 'Bob') }
      let!(:ind3) { create(:accredited_individual, :with_organizations, :with_location, first_name: 'Cindy') }
      let!(:ind4) { create(:accredited_individual, :with_organizations, :with_location, first_name: 'Debra') }

      it 'returns ok for a successful request' do
        get path, params: { type:, lat:, long: }

        expect(response).to have_http_status(:ok)
      end

      it 'returns the accredited individuals in the body' do
        get path, params: { type:, lat:, long: }

        parsed_response = JSON.parse(response.body)

        expect(parsed_response['data'].pluck('id')).to contain_exactly(ind1.id, ind2.id, ind3.id, ind4.id)
      end

      it 'surfaces each per-rep acceptance_mode on the nested organization' do
        ind1.accreditations.first.update!(acceptance_mode: 'any_request')
        ind2.accreditations.first.update!(acceptance_mode: 'self_only')
        # ind3 keeps the factory default (no_acceptance)

        get path, params: { type:, lat:, long: }

        parsed_response = JSON.parse(response.body)
        acceptance_mode_for = lambda do |individual|
          entry = parsed_response['data'].find { |e| e['id'] == individual.id }
          entry['attributes']['accredited_organizations']['data'].first['attributes']['acceptance_mode']
        end

        expect(acceptance_mode_for.call(ind1)).to eq('any_request')
        expect(acceptance_mode_for.call(ind2)).to eq('self_only')
        expect(acceptance_mode_for.call(ind3)).to eq('no_acceptance')
      end

      it 'paginates' do
        get path, params: { type:, lat:, long:, sort: 'first_name_asc', page: 1, per_page: 2 }

        parsed_response = JSON.parse(response.body)

        expect(parsed_response['data'].pluck('id')).to contain_exactly(ind1.id, ind2.id)
        expect(parsed_response['meta']['pagination']['current_page']).to eq(1)
        expect(parsed_response['meta']['pagination']['per_page']).to eq(2)
        expect(parsed_response['meta']['pagination']['total_pages']).to eq(2)
        expect(parsed_response['meta']['pagination']['total_entries']).to eq(4)
      end

      context 'when there are no results for the search criteria' do
        it 'returns an empty list' do
          get path, params: { type: 'claims_agent', lat:, long: }

          parsed_response = JSON.parse(response.body)

          expect(parsed_response['data']).to eq([])
          expect(parsed_response['meta']['pagination']['total_entries']).to eq(0)
        end
      end
    end
  end
end
