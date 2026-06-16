# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'RepresentationManagement::V0::AccreditedIndividuals', type: :request do
  let(:path) { '/representation_management/v0/accredited_individuals' }
  let(:type) { 'representative' }
  let(:distance) { 50 }
  let(:lat) { 42.65140884 }
  let(:long) { -73.77623285 }

  let(:data_ingestion_log_accreditation) { build_stubbed(:accreditation_data_ingestion_log) }
  let(:data_ingestion_log_trexler) { build_stubbed(:accreditation_data_ingestion_log, :trexler_file) }

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
      context 'when the current data source is the Accreditation API' do
        let!(:ind1) { create(:accredited_individual, :with_organizations, :with_location, first_name: 'August') }
        let!(:ind2) { create(:accredited_individual, :with_organizations, :with_location, first_name: 'Bob') }
        let!(:ind3) { create(:accredited_individual, :with_organizations, :with_location, first_name: 'Cindy') }
        let!(:ind4) { create(:accredited_individual, :with_organizations, :with_location, first_name: 'Debra') }

        before do
          expect(RepresentationManagement::AccreditationDataIngestionLog)
            .to receive(:most_recent_successful)
            .and_return(data_ingestion_log_accreditation)
        end

        it 'returns ok for a successful request' do
          get path, params: { type:, lat:, long: }

          expect(response).to have_http_status(:ok)
        end

        it 'returns the accredited individuals in the body' do
          get path, params: { type:, lat:, long: }

          parsed_response = JSON.parse(response.body)

          expect(parsed_response['data'].pluck('id')).to contain_exactly(ind1.id, ind2.id, ind3.id, ind4.id)
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

      context 'when the current data source is the Trexler file' do
        let!(:org) { create(:veteran_organization, poa: 'A1Q') }
        let!(:rep1) { create(:veteran_representative, :vso, :with_address, first_name: 'August') }
        let!(:rep2) { create(:veteran_representative, :vso, :with_address, first_name: 'Bob') }
        let!(:rep3) { create(:veteran_representative, :vso, :with_address, first_name: 'Cindy') }
        let!(:rep4) { create(:veteran_representative, :vso, :with_address, first_name: 'Debra') }

        before do
          expect(RepresentationManagement::AccreditationDataIngestionLog)
            .to receive(:most_recent_successful)
            .and_return(data_ingestion_log_trexler)
        end

        it 'returns ok for a successful request' do
          get path, params: { type:, lat:, long: }

          expect(response).to have_http_status(:ok)
        end

        it 'returns the veteran representatives in the body' do
          get path, params: { type:, lat:, long: }

          parsed_response = JSON.parse(response.body)

          expect(parsed_response['data'].pluck('id')).to contain_exactly(rep1.id, rep2.id, rep3.id, rep4.id)
        end

        it 'paginates' do
          get path, params: { type:, lat:, long:, sort: 'first_name_asc', page: 1, per_page: 2 }

          parsed_response = JSON.parse(response.body)

          expect(parsed_response['data'].pluck('id')).to contain_exactly(rep1.id, rep2.id)
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
end
