# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'RepresentationManagement::V0::OriginalEntities', type: :request do
  let(:path) { '/representation_management/v0/original_entities' }
  let!(:bob_law) do
    create(:representative, :with_address, representative_id: '00001', first_name: 'Bob', last_name: 'Law')
  end
  let!(:bob_smith) do
    create(:representative, :with_address, representative_id: '00002', first_name: 'Bob', last_name: 'Smith')
  end
  let!(:bob_law_firm) { create(:organization, :with_address, poa: 'ABC', name: 'Bob Law Firm') }
  let!(:bob_smith_firm) { create(:organization, :with_address, poa: 'DEF', name: 'Bob Smith Firm') }

  context 'when use_veteran_models_for_appoint is disabled' do
    before do
      allow(Flipper).to receive(:enabled?).with(:use_veteran_models_for_appoint).and_return(false)
    end

    it 'returns a not found routing error' do
      get path

      expect(response).to have_http_status(:not_found)
    end
  end

  context 'when use_veteran_models_for_appoint is enabled' do
    before do
      allow(Flipper).to receive(:enabled?).with(:use_veteran_models_for_appoint).and_return(true)
    end

    context 'when no query param is provided' do
      it 'returns an empty array' do
        get path

        parsed_response = JSON.parse(response.body)

        expect(response).to have_http_status(:success)
        expect(parsed_response).to eq([])
      end
    end

    context 'when the query string is blank' do
      it 'returns an empty array' do
        get path, params: { query: '' }

        parsed_response = JSON.parse(response.body)

        expect(response).to have_http_status(:success)
        expect(parsed_response).to eq([])
      end
    end

    context 'when the search yields no results' do
      it 'when there are no matching results' do
        get path, params: { query: 'Zach' }

        parsed_response = JSON.parse(response.body)

        expect(response).to have_http_status(:success)
        expect(parsed_response).to eq([])
      end
    end

    context 'when there are search results' do
      before do
        allow(Flipper).to receive(:enabled?).with(:appoint_a_representative_trigram_order_search,
                                                  any_args).and_return(false)
      end

      it 'returns an array of individuals and organizations' do
        get path, params: { query: 'Bob' }

        parsed_response = JSON.parse(response.body)

        expect(response).to have_http_status(:success)
        expect(parsed_response.size).to eq(4)
        expect(parsed_response[0]['data']['attributes']['full_name']).to eq('Bob Law')
        expect(parsed_response[1]['data']['attributes']['full_name']).to eq('Bob Smith')
        expect(parsed_response[2]['data']['attributes']['name']).to eq('Bob Law Firm')
        expect(parsed_response[3]['data']['attributes']['name']).to eq('Bob Smith Firm')
      end
    end

    context 'when there are search results (trigram flipper enabled)' do
      before do
        allow(Flipper).to receive(:enabled?).with(:appoint_a_representative_trigram_order_search,
                                                  any_args).and_return(true)
      end

      it 'returns an array of individuals and organizations' do
        get path, params: { query: 'Bob' }

        parsed_response = JSON.parse(response.body)

        expect(response).to have_http_status(:success)
        expect(parsed_response.size).to eq(4)
        expect(parsed_response[0]['data']['attributes']['name']).to eq('Bob Smith Firm')
        expect(parsed_response[1]['data']['attributes']['name']).to eq('Bob Law Firm')
        expect(parsed_response[2]['data']['attributes']['full_name']).to eq('Bob Smith')
        expect(parsed_response[3]['data']['attributes']['full_name']).to eq('Bob Law')
      end
    end

    describe 'org card acceptance fields' do
      let!(:org) do
        create(:organization, :with_address, poa: 'GHI', name: 'Test Org',
                                             can_accept_digital_poa_requests: true)
      end
      let!(:rep) do
        create(:representative, :with_address, representative_id: '00099',
                                               first_name: 'Test', last_name: 'Rep', poa_codes: ['GHI'])
      end

      describe 'can_accept_digital_poa_requests returns the raw org column value' do
        it 'for org cards' do
          get path, params: { query: 'Test Org' }

          parsed_response = JSON.parse(response.body)
          org_card = parsed_response.find { |r| r.dig('data', 'attributes', 'name') == 'Test Org' }

          expect(org_card.dig('data', 'attributes', 'can_accept_digital_poa_requests')).to be true
        end
      end

      describe 'reps_can_accept_any_request' do
        it 'returns true when an active any_request rep exists' do
          create(:veteran_organization_representative,
                 representative: rep, organization: org, acceptance_mode: 'any_request')

          get path, params: { query: 'Test Org' }

          parsed_response = JSON.parse(response.body)
          org_card = parsed_response.find { |r| r.dig('data', 'attributes', 'name') == 'Test Org' }

          expect(org_card.dig('data', 'attributes', 'reps_can_accept_any_request')).to be true
        end

        it 'returns false when only self_only reps exist' do
          create(:veteran_organization_representative,
                 representative: rep, organization: org, acceptance_mode: 'self_only')

          get path, params: { query: 'Test Org' }

          parsed_response = JSON.parse(response.body)
          org_card = parsed_response.find { |r| r.dig('data', 'attributes', 'name') == 'Test Org' }

          expect(org_card.dig('data', 'attributes', 'reps_can_accept_any_request')).to be false
        end

        it 'returns false when no organization_representative records exist' do
          get path, params: { query: 'Test Org' }

          parsed_response = JSON.parse(response.body)
          org_card = parsed_response.find { |r| r.dig('data', 'attributes', 'name') == 'Test Org' }

          expect(org_card.dig('data', 'attributes', 'reps_can_accept_any_request')).to be false
        end
      end

      describe 'rep cards with nested org' do
        it 'returns true for can_accept_digital_poa_requests when acceptance_mode is any_request' do
          create(:veteran_organization_representative,
                 representative: rep, organization: org, acceptance_mode: 'any_request')

          get path, params: { query: 'Test Rep' }

          parsed_response = JSON.parse(response.body)
          rep_card = parsed_response.find { |r| r.dig('data', 'attributes', 'full_name') == 'Test Rep' }
          nested_orgs = rep_card.dig('data', 'attributes', 'accredited_organizations', 'data')
          nested_org = nested_orgs.find { |o| o.dig('attributes', 'name') == 'Test Org' }

          expect(nested_org.dig('attributes', 'can_accept_digital_poa_requests')).to be true
        end

        it 'returns true for can_accept_digital_poa_requests when acceptance_mode is self_only' do
          create(:veteran_organization_representative,
                 representative: rep, organization: org, acceptance_mode: 'self_only')

          get path, params: { query: 'Test Rep' }

          parsed_response = JSON.parse(response.body)
          rep_card = parsed_response.find { |r| r.dig('data', 'attributes', 'full_name') == 'Test Rep' }
          nested_orgs = rep_card.dig('data', 'attributes', 'accredited_organizations', 'data')
          nested_org = nested_orgs.find { |o| o.dig('attributes', 'name') == 'Test Org' }

          expect(nested_org.dig('attributes', 'can_accept_digital_poa_requests')).to be true
        end

        it 'returns false for can_accept_digital_poa_requests when acceptance_mode is no_acceptance' do
          create(:veteran_organization_representative,
                 representative: rep, organization: org, acceptance_mode: 'no_acceptance')

          get path, params: { query: 'Test Rep' }

          parsed_response = JSON.parse(response.body)
          rep_card = parsed_response.find { |r| r.dig('data', 'attributes', 'full_name') == 'Test Rep' }
          nested_orgs = rep_card.dig('data', 'attributes', 'accredited_organizations', 'data')
          nested_org = nested_orgs.find { |o| o.dig('attributes', 'name') == 'Test Org' }

          expect(nested_org.dig('attributes', 'can_accept_digital_poa_requests')).to be false
        end

        it 'does not include reps_can_accept_any_request' do
          create(:veteran_organization_representative,
                 representative: rep, organization: org, acceptance_mode: 'any_request')

          get path, params: { query: 'Test Rep' }

          parsed_response = JSON.parse(response.body)
          rep_card = parsed_response.find { |r| r.dig('data', 'attributes', 'full_name') == 'Test Rep' }
          nested_orgs = rep_card.dig('data', 'attributes', 'accredited_organizations', 'data')
          nested_org = nested_orgs.find { |o| o.dig('attributes', 'name') == 'Test Org' }

          expect(nested_org['attributes']).not_to have_key('reps_can_accept_any_request')
        end
      end
    end
  end
end
